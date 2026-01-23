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
};

pub const Export = struct {
    const Self = @This();
    const Stack = std.ArrayList(bool);

    env: Env,
    config: *const cfg.file.Config,
    cli_args: *const cfg.cli.Args,
    forest: *mero.Forest,
    stack: Stack = .{},

    pub fn deinit(self: *Self) void {
        self.stack.deinit(self.env.a);
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

            a: std.mem.Allocator,
            io: std.Io,
            tree: *mero.Tree,
            stack: *Stack,
            needle: []const u8,
            output_dir: *std.Io.Dir,
            output: *std.Io.Writer,
            terms: []const mero.Term = &.{},
            section_level: usize = 0,
            section_id: usize = 0,
            add_newline_before_bullet: bool = false,
            write_section_id_on_newline: bool = false,
            mode: Mode = .Search,

            pub fn call(my: *@This(), entry: mero.Tree.Entry, before: bool) !void {
                const n: *const mero.Node = entry.data;

                switch (my.mode) {
                    .Search => {
                        switch (n.type) {
                            .Folder => {
                                if (before) {
                                    try my.stack.append(my.a, false);
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
                            if (before)
                                my.section_level += 1
                            else
                                my.section_level -= 1;
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
                                            try my.output_dir.createDirPath(my.io, std.fs.path.dirname(filepath) orelse ".");

                                            const src_folder = std.fs.path.dirname(n.path) orelse return error.ExpectedAbsolutePath;
                                            var src_dir = try std.Io.Dir.openDirAbsolute(my.io, src_folder, .{});
                                            defer src_dir.close(my.io);

                                            // &improv: check that we will not overwrite an file with the same relative name
                                            std.debug.print("Coping '{s}' from '{s}'\n", .{ filepath, src_folder });
                                            try src_dir.copyFile(filepath, my.output_dir.*, filepath, my.io, .{});
                                        }
                                    },
                                    .Newline => {
                                        if (n.type == .Section) {
                                            try my.output.print(" {{#section:{}}}", .{my.section_id});
                                            my.section_id += 1;
                                        }
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
                .a = self.env.a,
                .io = self.env.io,
                .tree = &self.forest.tree,
                .stack = &self.stack,
                .needle = needle,
                .output_dir = &output_dir,
                .output = &output_w.interface,
            };
            try self.forest.tree.dfsAll(&cb);
        }

        try output_w.interface.flush();
    }
};
