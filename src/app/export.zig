const std = @import("std");

const rubr = @import("rubr");
const Env = rubr.Env;
const lsp = rubr.lsp;
const strings = rubr.strings;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const qry = @import("../qry.zig");
const amp = @import("../amp.zig");
const markdown = @import("../markdown.zig");

pub const Error = error{
    UnexpectedEmptyStack,
    ExpectedAbsolutePath,
    CouldNotFindSection,
};

pub const Export = struct {
    const Self = @This();
    const BoolStack = std.ArrayList(bool);
    const NodeIds = std.ArrayList(usize);

    const SectionTasks = struct {
        const TaskNids = std.ArrayList(usize);
        section_id: i64,
        section_nid: usize,
        task_nids: NodeIds = .{},
        terms: []const mero.Term = &.{},
    };
    const SectionTasksList = std.ArrayList(SectionTasks);

    env: Env,
    config: *const cfg.file.Config,
    cli_args: *const cfg.cli.Args,
    forest: *mero.Forest,
    stack: BoolStack = .{},
    sectiontasks_list: SectionTasksList = .{},

    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.env.a);
        for (self.sectiontasks_list.items) |*sectiontasks|
            sectiontasks.task_nids.deinit(self.env.a);
        self.sectiontasks_list.deinit(self.env.a);
    }

    pub fn call(self: *Self, query_input: [][]const u8) !void {
        var output_dir = try std.Io.Dir.cwd().createDirPathOpen(self.env.io, self.cli_args.output orelse ".", .{});
        defer output_dir.close(self.env.io);

        var output_file = try output_dir.createFile(self.env.io, "content.md", .{});
        defer output_file.close(self.env.io);

        var bufw: [4096]u8 = undefined;
        var output_w = output_file.writer(self.env.io, &bufw);

        const Cb = struct {
            const Mode = enum { Search, Write };

            env: rubr.Env,
            tree: *mero.Tree,
            stack: *BoolStack,
            sectiontasks_list: *SectionTasksList,
            needle: []const u8,
            output_dir: *std.Io.Dir,
            output: *std.Io.Writer,
            terms: []const mero.Term = &.{},
            section_level: usize = 0,
            section_nid_stack: NodeIds = .{},
            section_id: i64 = -1,
            add_newline_before_bullet: bool = false,
            write_section_id_on_newline: bool = false,
            mode: Mode = .Search,

            fn deinit(my: *@This()) void {
                my.section_nid_stack.deinit(my.env.a);
            }

            pub fn call(my: *@This(), entry: mero.Tree.Entry, before: bool) !void {
                const n: *const mero.Node = entry.data;

                switch (my.mode) {
                    .Search => {
                        switch (n.type) {
                            .Folder => {
                                if (before) {
                                    try my.stack.append(my.env.a, false);
                                } else {
                                    if (my.stack.pop()) |saw_folder_metadata| {
                                        if (saw_folder_metadata)
                                            my.section_level -= 1;
                                    }
                                }
                            },
                            .File => {
                                if (before) {
                                    if (std.mem.find(u8, n.path, my.needle)) |_| {
                                        std.debug.print("{}: {s} {}\n", .{ my.section_level, n.path, n.terms.items.len });

                                        my.mode = .Write;
                                        my.terms = n.terms.items;
                                        for (my.tree.childIds(entry.id)) |child_id| {
                                            try my.tree.dfs(child_id, my);
                                        }
                                        try my.output.print("\n", .{});
                                        my.terms = &.{};
                                        my.mode = .Search;

                                        if (amp.is_folder_metadata_fp(n.path)) {
                                            const saw_folder_metadata = rubr.slc.lastPtr(my.stack.items) orelse return error.UnexpectedEmptyStack;
                                            saw_folder_metadata.* = true;
                                            my.section_level += 1;
                                        }
                                    }
                                }
                            },
                            else => {},
                        }
                    },
                    .Write => {
                        if (n.type == .Section) {
                            if (before) {
                                my.section_level += 1;
                                try my.section_nid_stack.append(my.env.a, entry.id);
                            } else {
                                my.section_level -= 1;
                                _ = my.section_nid_stack.pop();
                            }
                        }

                        if (!before)
                            return;

                        for (n.line.terms_ixr.begin..n.line.terms_ixr.end) |ix| {
                            const term = my.terms[ix];
                            if (false)
                                try my.output.print("[{any}]({s})", .{ term.kind, term.word })
                            else {
                                var do_write: bool = true;
                                switch (term.kind) {
                                    .Amp => {
                                        // Skip amp
                                        do_write = false;
                                    },
                                    .Section => {
                                        // We write the section depth ourselves
                                        for (0..my.section_level) |_|
                                            try my.output.writeByte('#');
                                        try my.output.writeByte(' ');
                                        do_write = false;
                                    },

                                    .Bullet => {
                                        if (my.add_newline_before_bullet)
                                            try my.output.print("\n", .{});
                                    },
                                    .Link => {
                                        const link = markdown.Link{ .content = term.word };

                                        if (link.image_filepath()) |filepath| {
                                            // Create destination folder
                                            try my.output_dir.createDirPath(my.env.io, std.fs.path.dirname(filepath) orelse ".");

                                            const src_folder = std.fs.path.dirname(n.path) orelse return error.ExpectedAbsolutePath;
                                            var src_dir = try std.Io.Dir.openDirAbsolute(my.env.io, src_folder, .{});
                                            defer src_dir.close(my.env.io);

                                            // &improv: check that we will not overwrite an file with the same relative name
                                            std.debug.print("Coping '{s}' from '{s}'\n", .{ filepath, src_folder });
                                            try src_dir.copyFile(filepath, my.output_dir.*, filepath, my.env.io, .{});
                                        }
                                    },
                                    .Newline => {
                                        if (n.type == .Section) {
                                            my.section_id += 1;
                                            try my.output.print(" {{#section:{}}}", .{my.section_id});
                                        }
                                    },
                                    .Checkbox => {
                                        const section_nid = my.section_nid_stack.getLastOrNull() orelse {
                                            try my.env.log.err("Found a checkbok in '{s}' outside a section\n", .{n.path});
                                            return error.CouldNotFindSection;
                                        };
                                        if (rubr.slc.lastPtr(my.sectiontasks_list.items)) |sectiontasks| {
                                            if (sectiontasks.section_nid != section_nid)
                                                try my.sectiontasks_list.append(my.env.a, SectionTasks{ .section_id = my.section_id, .section_nid = section_nid, .terms = my.terms });
                                        } else {
                                            try my.sectiontasks_list.append(my.env.a, SectionTasks{ .section_id = my.section_id, .section_nid = section_nid, .terms = my.terms });
                                        }
                                        const sectiontasks = rubr.slc.lastPtrUnsafe(my.sectiontasks_list.items);
                                        try sectiontasks.task_nids.append(my.env.a, entry.id);
                                    },
                                    else => {},
                                }
                                if (do_write)
                                    try my.output.print("{s}", .{term.word});
                            }
                        }

                        my.add_newline_before_bullet = n.type == .Paragraph;
                    },
                }
            }
        };

        const default_query_input: [1][]const u8 = .{""};
        const needles = if (rubr.slc.isEmpty(query_input)) &default_query_input else query_input;

        for (needles) |needle| {
            var cb = Cb{
                .env = self.env,
                .tree = &self.forest.tree,
                .stack = &self.stack,
                .sectiontasks_list = &self.sectiontasks_list,
                .needle = needle,
                .output_dir = &output_dir,
                .output = &output_w.interface,
            };
            defer cb.deinit();
            try self.forest.tree.dfsAll(&cb);
        }

        if (!rubr.slc.isEmpty(self.sectiontasks_list.items)) {
            const w = &output_w.interface;
            try w.print("\n# Open tasks\n\n", .{});
            try w.print("This section provides on overview of the open tasks per section in above document.\n\n", .{});
            for (self.sectiontasks_list.items) |sectiontasks| {
                {
                    try w.print("## [", .{});
                    const n: *const mero.Node = try self.forest.tree.cget(sectiontasks.section_nid);
                    for (n.line.terms_ixr.begin..n.line.terms_ixr.end) |ix| {
                        const term = sectiontasks.terms[ix];
                        switch (term.kind) {
                            .Section, .Newline => {},
                            else => try w.print("{s}", .{term.word}),
                        }
                    }
                    try w.print("](#section:{})\n\n", .{sectiontasks.section_id});
                }

                for (sectiontasks.task_nids.items) |task_nid| {
                    try w.print("- ", .{});
                    const n: *const mero.Node = try self.forest.tree.cget(task_nid);
                    for (n.line.terms_ixr.begin..n.line.terms_ixr.end) |ix| {
                        const term = sectiontasks.terms[ix];
                        switch (term.kind) {
                            .Section, .Bullet, .Checkbox => {},
                            else => try w.print("{s}", .{term.word}),
                        }
                    }
                }
            }
        }

        try output_w.interface.flush();
    }
};
