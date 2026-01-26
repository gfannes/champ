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
    const ChoreIds = std.ArrayList(usize);

    env: Env,
    config: *const cfg.file.Config,
    cli_args: *const cfg.cli.Args,
    forest: *mero.Forest,
    stack: BoolStack = .{},
    chore_ids: ChoreIds = .{},

    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.env.a);
        self.chore_ids.deinit(self.env.a);
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
            chore_ids: *ChoreIds,
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
                            .folder => {
                                if (before) {
                                    try my.stack.append(my.env.a, false);
                                } else {
                                    if (my.stack.pop()) |saw_folder_metadata| {
                                        if (saw_folder_metadata)
                                            my.section_level -= 1;
                                    }
                                }
                            },
                            .file => |file| {
                                if (before) {
                                    if (std.mem.find(u8, n.path, my.needle)) |_| {
                                        std.debug.print("{}: {s} {}\n", .{ my.section_level, n.path, file.terms.items.len });

                                        my.mode = .Write;
                                        my.terms = file.terms.items;
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
                        if (n.type == .section) {
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

                        if (n.chore_id) |chore_id|
                            try my.chore_ids.append(my.env.a, chore_id);

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
                                        if (n.type == .section)
                                            try my.output.print(" {{#section:{}}}", .{entry.id});
                                    },
                                    else => {},
                                }
                                if (do_write)
                                    try my.output.print("{s}", .{term.word});
                            }
                        }

                        my.add_newline_before_bullet = n.type == .paragraph;
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
                .chore_ids = &self.chore_ids,
                .needle = needle,
                .output_dir = &output_dir,
                .output = &output_w.interface,
            };
            defer cb.deinit();
            try self.forest.tree.dfsAll(&cb);
        }

        if (!rubr.slc.isEmpty(self.chore_ids.items)) {
            const w = &output_w.interface;
            try w.print("\n# Tasks\n\n", .{});
            try w.print("This section provides on overview of the open and closed tasks per section in above document.\n", .{});
            for (&[_]bool{ false, true }) |is_done| {
                try w.print("\n## {s} tasks\n\n", .{if (is_done) "Closed" else "Open"});

                var prev_section: ?*const mero.Node = null;
                for (self.chore_ids.items) |chore_id| {
                    const chore = &self.forest.chores.list.items[chore_id];
                    if (chore.isDone() != is_done)
                        continue;

                    const Ancestors = struct {
                        section: ?*const mero.Node = null,
                        section_id: ?usize = null,
                        file: ?*const mero.Node = null,
                        pub fn call(an: *@This(), entry: *const mero.Tree.Entry) void {
                            switch (entry.data.type) {
                                .section => if (an.section == null) {
                                    an.section = entry.data;
                                    an.section_id = entry.id;
                                },
                                .file => if (an.file == null) {
                                    an.file = entry.data;
                                },
                                else => {},
                            }
                        }
                    };
                    var ancestors = Ancestors{};
                    self.forest.tree.toRoot(chore.node_id, &ancestors);

                    if (ancestors.section != prev_section)
                        prev_section = null;

                    if (prev_section == null) {
                        if (ancestors.section) |section| {
                            try w.print("\n### [", .{});
                            if (ancestors.file) |file| {
                                for (section.line.terms_ixr.begin..section.line.terms_ixr.end) |ix| {
                                    const term = file.type.file.terms.items[ix];
                                    switch (term.kind) {
                                        .Section, .Amp, .Checkbox, .Capital, .Newline => {},
                                        else => try w.print("{s}", .{term.word}),
                                    }
                                }
                            }
                            try w.print("](#section:{})\n\n", .{ancestors.section_id.?});
                            prev_section = section;
                        }
                    }

                    {
                        var first: bool = true;
                        const n = self.forest.tree.cptr(chore.node_id);
                        for (n.line.terms_ixr.begin..n.line.terms_ixr.end) |ix| {
                            if (ancestors.file) |file| {
                                const term = file.type.file.terms.items[ix];
                                switch (term.kind) {
                                    .Section, .Bullet, .Checkbox, .Amp, .Capital, .Newline => {},
                                    else => {
                                        if (first) {
                                            first = false;
                                            try w.print("- ", .{});
                                        }
                                        try w.print("{s}", .{term.word});
                                    },
                                }
                            }
                        }
                        if (!first)
                            try w.print("\n", .{});
                    }
                }
            }
        }

        try output_w.interface.flush();
    }
};
