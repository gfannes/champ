const std = @import("std");

const Log = @import("rubr").log.Log;
const lsp = @import("rubr").lsp;
const strings = @import("rubr").strings;

const cfg = @import("../cfg.zig");
const cli = @import("../cli.zig");
const mero = @import("../mero.zig");

pub const Test = struct {
    const Self = @This();

    config: *const cfg.Config,
    options: *const cli.Options,
    log: *const Log,
    a: std.mem.Allocator,

    forest: mero.Forest = undefined,

    pub fn init(self: *Self) !void {
        self.forest = mero.Forest.init(self.log, self.a);
    }
    pub fn deinit(self: *Self) void {
        self.forest.deinit();
    }

    pub fn call(self: *Self) !void {
        for (self.config.groves) |cfg_grove| {
            if (!strings.contains(u8, self.options.groves.items, cfg_grove.name))
                // Skip this grove
                continue;
            try self.forest.loadGrove(&cfg_grove);
        }
        // for (self.forest.groves.items) |grove| {
        //     std.debug.print("{any}\n", .{grove});
        // }

        var iter = self.forest.iter();
        while (iter.next()) |e| {
            std.debug.print("{s} {s}\n", .{ e.name, e.path });
        }
    }
};
