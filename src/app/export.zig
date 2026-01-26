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
    ExpectedAbsolutePath,
    CouldNotFindSection,
    ExpectedSection,
    ExpectedWbs,
};

pub const Export = struct {
    const Self = @This();
    const BoolStack = std.ArrayList(bool);
    const Section = struct {
        id: usize,
        wbs: ?amp.Wbs.Kind = null,
    };
    const SectionStack = std.ArrayList(Section);
    const SectionChores = std.AutoArrayHashMapUnmanaged(usize, std.ArrayList(usize));
    const Chore = struct {
        id: usize,
        section: usize,
    };

    env: Env,
    config: *const cfg.file.Config,
    cli_args: *const cfg.cli.Args,
    forest: *mero.Forest,
    stack: BoolStack = .{},
    section_chores: SectionChores = .{},

    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.env.a);
        {
            var it = self.section_chores.iterator();
            while (it.next()) |e|
                e.value_ptr.deinit(self.env.a);
            self.section_chores.deinit(self.env.a);
        }
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
            chores: *const chore.Chores,
            section_chores: *SectionChores,
            needle: []const u8,
            output_dir: *std.Io.Dir,
            output: *std.Io.Writer,
            terms: []const mero.Term = &.{},
            section_level: usize = 0,
            section_stack: SectionStack = .{},
            add_newline_before_bullet: bool = false,
            write_section_id_on_newline: bool = false,
            mode: Mode = .Search,
            first_section: ?Section = null,

            fn deinit(my: *@This()) void {
                my.section_stack.deinit(my.env.a);
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
                                    if (my.stack.pop()) |has_section| {
                                        if (has_section) {
                                            my.section_level -= 1;
                                            _ = my.section_stack.pop();
                                        }
                                    }
                                }
                            },
                            .file => |file| {
                                if (before) {
                                    if (std.mem.find(u8, n.path, my.needle)) |_| {
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
                                                const has_section = rubr.slc.lastPtr(my.stack.items) orelse return error.UnexpectedEmptyStack;
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

        for (needles) |needle| {
            var cb = Cb{
                .env = self.env,
                .tree = &self.forest.tree,
                .stack = &self.stack,
                .chores = &self.forest.chores,
                .section_chores = &self.section_chores,
                .needle = needle,
                .output_dir = &output_dir,
                .output = &output_w.interface,
            };
            defer cb.deinit();
            try self.forest.tree.dfsAll(&cb);
        }

        {
            const w = &output_w.interface;
            try w.print("\n# Tasks\n\n", .{});
            try w.print("This section provides on overview of the open and closed tasks per section in above document.\n", .{});

            var act_section_id: ?usize = null;

            var it = self.section_chores.iterator();
            while (it.next()) |e| {
                const section_id = e.key_ptr.*;
                for (e.value_ptr.items) |chore_id| {
                    const ch = &self.forest.chores.list.items[chore_id];

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

                    if (act_section_id != section_id)
                        act_section_id = null;

                    if (act_section_id == null) {
                        act_section_id = section_id;
                        const section = try self.forest.tree.cget(section_id);

                        try w.print("\n### [", .{});
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
                        try w.print("](#section:{})\n\n", .{section_id});
                    }

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

        try output_w.interface.flush();
    }
};
