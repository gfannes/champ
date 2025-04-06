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

    pub const Iter = struct {
        pub const Value = struct {
            name: []const u8,
            path: []const u8,
        };

        outer: *const Self,
        grove_ix: usize = 0,
        file_ix: usize = 0,

        pub fn next(self: *Iter) ?Value {
            const value: Value = switch (self.grove_ix) {
                0 => Value{ .name = "name0", .path = "path0" },
                1 => Value{ .name = "name1", .path = "path1" },
                2 => Value{ .name = "name2", .path = "path2" },
                else => return null,
            };
            self.grove_ix += 1;
            return value;
        }
    };

    pub fn iter(self: Self) Iter {
        return Iter{ .outer = &self };
    }
};
