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
            haystack: [][]const u8,
            pub fn call(my: @This(), entry: mero.Tree.Entry, before: bool) !void {
                if (!before)
                    return;
                const n: *const mero.Node = entry.data;
                if (n.type == .File) {
                    var do_include: bool = false;
                    for (my.haystack) |needle| {
                        if (std.mem.find(u8, n.path, needle)) |_|
                            do_include = true;
                    }
                    if (do_include)
                        std.debug.print("{s}\n", .{n.path});
                }
            }
        };
        const cb = Cb{ .haystack = query_input };
        try self.forest.tree.dfsAll(&cb);
    }
};
