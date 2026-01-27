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
const chore = @import("../chore.zig");

pub const Error = error{
    UnexpectedEmptyStack,
    UnexpectedStatus,
    CouldNotFindSection,
    ExpectedAbsolutePath,
    ExpectedSection,
    ExpectedWbs,
    ExpectedNeedle,
};

pub const Export = struct {
    const Self = @This();

    env: Env,
    config: *const cfg.file.Config,
    cli_args: *const cfg.cli.Args,
    forest: *mero.Forest,

    pub fn deinit(_: *Self) void {}

    pub fn call(self: *Self, query_input: [][]const u8) !void {
        var output_dir = try std.Io.Dir.cwd().createDirPathOpen(self.env.io, self.cli_args.output orelse ".", .{});
        defer output_dir.close(self.env.io);

        var output_file = try output_dir.createFile(self.env.io, "content.md", .{});
        defer output_file.close(self.env.io);

        var bufw: [4096]u8 = undefined;
        var output_w = output_file.writer(self.env.io, &bufw);

        const Cb = struct {
            const Mode = enum { Search, Write };
            const BoolStack = std.ArrayList(bool);
            const Section = struct {
                id: usize,
                wbs: ?amp.Wbs.Kind = null,
            };
            const SectionStack = std.ArrayList(Section);
            const SectionChoreIds = std.AutoArrayHashMapUnmanaged(usize, std.ArrayList(usize));

            env: rubr.Env,
            tree: *mero.Tree,
            chores: *const chore.Chores,
            output_dir: *std.Io.Dir,
            output: *std.Io.Writer,

            needle: ?[]const u8 = null,

            // Indicates if a folder has a metadata file '&.md' with a section in it. If so, this will be used to nest the sections from other files.
            has_section_stack: BoolStack = .{},

            section_chores: SectionChoreIds = .{},
            terms: []const mero.Term = &.{},
            section_level: usize = 0,
            section_stack: SectionStack = .{},
            add_newline_before_bullet: bool = false,
            write_section_id_on_newline: bool = false,
            mode: Mode = .Search,
            first_section: ?Section = null,

            fn deinit(my: *@This()) void {
                my.has_section_stack.deinit(my.env.a);
                my.section_stack.deinit(my.env.a);
                {
                    var it = my.section_chores.iterator();
                    while (it.next()) |e|
                        e.value_ptr.deinit(my.env.a);
                    my.section_chores.deinit(my.env.a);
                }
            }

            pub fn call(my: *@This(), entry: mero.Tree.Entry, before: bool) !void {
                const needle = my.needle orelse return error.ExpectedNeedle;

                const n: *const mero.Node = entry.data;

                switch (my.mode) {
                    .Search => {
                        switch (n.type) {
                            .folder => {
                                if (before) {
                                    try my.has_section_stack.append(my.env.a, false);
                                } else {
                                    if (my.has_section_stack.pop()) |has_section| {
                                        if (has_section) {
                                            my.section_level -= 1;
                                            _ = my.section_stack.pop();
                                        }
                                    }
                                }
                            },
                            .file => |file| {
                                if (before) {
                                    if (std.mem.find(u8, n.path, needle)) |_| {
                                        std.debug.print("{}: {s} {}\n", .{ my.section_level, n.path, file.terms.items.len });

                                        my.mode = .Write;
                                        my.terms = file.terms.items;
                                        my.first_section = null;
                                        for (my.tree.childIds(entry.id)) |child_id| {
                                            try my.tree.dfs(child_id, my);
                                        }
                                        try my.output.print("\n", .{});
                                        my.terms = &.{};
                                        my.mode = .Search;

                                        if (amp.is_folder_metadata_fp(n.path)) {
                                            if (my.first_section) |section| {
                                                std.debug.print("Found section in md folder: {}\n", .{section.id});
                                                const has_section = rubr.slc.lastPtr(my.has_section_stack.items) orelse return error.UnexpectedEmptyStack;
                                                has_section.* = true;
                                                my.section_level += 1;
                                                try my.section_stack.append(my.env.a, section);
                                            }
                                        }
                                    }
                                }
                            },
                            else => {},
                        }
                    },
                    .Write => {
                        // We record the section_id _before_ we add any potential id: a section itself is attributed to its parent
                        const maybe_section: ?Section = rubr.slc.last(my.section_stack.items);

                        if (n.type == .section) {
                            if (before) {
                                my.section_level += 1;
                                var section = Section{ .id = entry.id };
                                if (n.chore_id) |chore_id| {
                                    if (my.chores.list.items[chore_id].value("wbs", .Org)) |wbs_value| {
                                        const wbs = wbs_value.wbs orelse return error.ExpectedWbs;
                                        section.wbs = wbs.kind;
                                    }
                                }
                                if (maybe_section) |s| {
                                    if (s.wbs == .Epic)
                                        // We do not go deeper than an epic
                                        section = s;
                                }
                                try my.section_stack.append(my.env.a, section);
                                if (my.first_section == null)
                                    my.first_section = section;
                            } else {
                                my.section_level -= 1;
                                _ = my.section_stack.pop();
                            }
                        }

                        if (!before)
                            return;

                        if (n.chore_id) |chore_id| {
                            const section = maybe_section orelse {
                                try my.env.log.err("Chore {} has no parent section\n", .{chore_id});
                                return error.ExpectedSection;
                            };
                            const res = try my.section_chores.getOrPut(my.env.a, section.id);
                            if (!res.found_existing)
                                res.value_ptr.* = .{};
                            try res.value_ptr.append(my.env.a, chore_id);
                        }

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

        var cb = Cb{
            .env = self.env,
            .tree = &self.forest.tree,
            .chores = &self.forest.chores,
            .output_dir = &output_dir,
            .output = &output_w.interface,
        };
        defer cb.deinit();

        for (needles) |needle| {
            cb.needle = needle;
            try self.forest.tree.dfsAll(&cb);
        }

        const Ancestors = struct {
            file: ?*const mero.Node = null,
            pub fn call(an: *@This(), entry: *const mero.Tree.Entry) void {
                switch (entry.data.type) {
                    .file => if (an.file == null) {
                        an.file = entry.data;
                    },
                    else => {},
                }
            }
        };

        {
            const w = &output_w.interface;
            try w.print("\n# Tasks\n\n", .{});
            try w.print("This section provides on overview of the open and closed tasks per section in above document.\n", .{});

            var it = cb.section_chores.iterator();
            while (it.next()) |e| {
                const section_id = e.key_ptr.*;

                const Status_ChoreIds = std.AutoArrayHashMapUnmanaged(amp.Status.Kind, std.ArrayList(usize));
                var status_choreids = Status_ChoreIds{};
                defer {
                    var it_ = status_choreids.iterator();
                    while (it_.next()) |*e_| {
                        e_.value_ptr.deinit(self.env.a);
                    }
                    status_choreids.deinit(self.env.a);
                }
                {
                    const chore_ids = e.value_ptr.items;
                    for (chore_ids) |chore_id| {
                        const ch = &self.forest.chores.list.items[chore_id];

                        const status_value = ch.value("status", .Org) orelse continue;
                        var status = (status_value.status orelse continue).kind;
                        switch (status) {
                            .Blocked, .Todo, .Wip, .Done => {},
                            .Next, .Question => status = .Todo,
                            else => continue,
                        }

                        var gop = try status_choreids.getOrPut(self.env.a, status);
                        if (!gop.found_existing)
                            gop.value_ptr.* = .{};
                        try gop.value_ptr.append(self.env.a, chore_id);
                    }
                }

                if (status_choreids.entries.len > 0) {
                    // Write title
                    {
                        const section = try self.forest.tree.cget(section_id);

                        try w.print("\n### ", .{});
                        var ancestors = Ancestors{};
                        self.forest.tree.toRoot(section_id, &ancestors);
                        if (ancestors.file) |file| {
                            var trim: []const u8 = " ";
                            var maybe_word: ?[]const u8 = null;
                            for (section.line.terms_ixr.begin..section.line.terms_ixr.end) |ix| {
                                const term = file.type.file.terms.items[ix];
                                switch (term.kind) {
                                    .Section, .Amp, .Checkbox, .Capital, .Newline => {},
                                    else => {
                                        if (maybe_word) |word| {
                                            try w.print("{s}", .{std.mem.trimStart(u8, word, trim)});
                                            trim = "";
                                        }
                                        maybe_word = term.word;
                                    },
                                }
                            }
                            if (maybe_word) |word|
                                try w.print("{s}", .{std.mem.trimEnd(u8, std.mem.trimStart(u8, word, trim), " ")});
                        }
                        try w.print("\n\nDetailed description can be found [here](#section:{}).\n\n", .{section_id});
                    }

                    for (&[_]amp.Status.Kind{ .Blocked, .Todo, .Wip, .Done }) |status| {
                        const chore_ids = (status_choreids.getPtr(status) orelse continue).items;
                        if (rubr.slc.isEmpty(chore_ids))
                            continue;

                        const str = switch (status) {
                            .Blocked => "Blocked",
                            .Todo => "Todo",
                            .Wip => "In progress",
                            .Done => "Done",
                            else => return error.UnexpectedStatus,
                        };
                        try w.print("\n#### {s}\n\n", .{str});

                        for (chore_ids) |chore_id| {
                            const ch = &self.forest.chores.list.items[chore_id];

                            {
                                var first: bool = true;
                                const n = self.forest.tree.cptr(ch.node_id);
                                var ancestors = Ancestors{};
                                self.forest.tree.toRoot(ch.node_id, &ancestors);
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
            }
        }

        try output_w.interface.flush();
    }
};
