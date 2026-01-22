const std = @import("std");

const rubr = @import("rubr");
const Env = rubr.Env;
const lsp = rubr.lsp;
const strings = rubr.strings;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const qry = @import("../qry.zig");

pub const Export = struct {
    const Self = @This();

    env: Env,
    config: *const cfg.file.Config,
    cli_args: *const cfg.cli.Args,
    forest: *mero.Forest,

    pub fn deinit(_: *Self) void {}

    pub fn call(self: *Self, query_input: [][]const u8) !void {
        if (self.cli_args.output) |output|
            std.debug.print("Writing output to '{s}'.\n", .{output});

        const Cb = struct {
            needle: []const u8,
            first: bool = false,
            pub fn call(my: *@This(), entry: mero.Tree.Entry, before: bool) !void {
                const n: *const mero.Node = entry.data;
                switch (n.type) {
                    .Folder => {
                        my.first = before;
                    },
                    .File => {
                        if (before) {
                            if (std.mem.find(u8, n.path, my.needle)) |_|
                                std.debug.print("{s}{s}\n", .{if (my.first) "*" else "", n.path});
                            my.first = false;
                        }
                    },
                    else => {},
                }
            }
        };
        for (query_input) |needle| {
            var cb = Cb{ .needle = needle };
            try self.forest.tree.dfsAll(&cb);
        }
    }
};
