const std = @import("std");

const rubr = @import("rubr");
const Env = rubr.Env;
const lsp = rubr.lsp;
const strings = rubr.strings;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const qry = @import("../qry.zig");
const amp = @import("../amp.zig");

pub const Error = error{
    UnexpectedEmptyStack,
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
        if (self.cli_args.output) |output|
            std.debug.print("Writing output to '{s}'.\n", .{output});

        const Cb = struct {
            a: std.mem.Allocator,
            stack: *Stack,
            needle: []const u8,
            level: usize = 0,
            pub fn call(my: *@This(), entry: mero.Tree.Entry, before: bool) !void {
                const n: *const mero.Node = entry.data;
                switch (n.type) {
                    .Folder => {
                        if (before) {
                            try my.stack.append(my.a, false);
                        } else {
                            if (my.stack.pop()) |saw_folder_metadata| {
                                if (saw_folder_metadata)
                                    my.level -= 1;
                            }
                        }
                    },
                    .File => {
                        if (before) {
                            if (std.mem.find(u8, n.path, my.needle)) |_| {
                                std.debug.print("{}: {s}\n", .{ my.level, n.path });
                                if (amp.is_folder_metadata_fp(n.path)) {
                                    const saw_folder_metadata = rubr.slc.lastPtr(my.stack.items) orelse return error.UnexpectedEmptyStack;
                                    saw_folder_metadata.* = true;
                                    my.level += 1;
                                }
                            }
                        }
                    },
                    else => {},
                }
            }
        };
        for (query_input) |needle| {
            var cb = Cb{ .a = self.env.a, .stack = &self.stack, .needle = needle };
            try self.forest.tree.dfsAll(&cb);
        }
    }
};
