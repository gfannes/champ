const std = @import("std");

const Grove = @import("dto.zig").Grove;
const cfg = @import("../cfg.zig");

const Log = @import("rubr").log.Log;

pub const Forest = struct {
    const Self = @This();
    const Groves = std.ArrayList(Grove);

    log: *const Log,
    groves: Groves = undefined,
    a: std.mem.Allocator,

    pub fn init(log: *const Log, a: std.mem.Allocator) Self {
        return Self{ .log = log, .groves = Groves.init(a), .a = a };
    }
    pub fn deinit(self: *Self) void {
        self.parser.deinit();
        for (self.groves) |*grove|
            grove.deinit();
        self.groves.deinit();
    }

    pub fn loadGrove(self: *Self, cfg_grove: *const cfg.Grove) !void {
        var grove = try Grove.init(self.log, self.a);
        try grove.load(cfg_grove);
        try self.groves.append(grove);
    }
};
