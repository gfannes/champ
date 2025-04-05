const std = @import("std");

const Grove = @import("dto.zig").Grove;

pub const Forest = struct {
    const Self = @This();
    const Groves = std.ArrayList(Grove);

    groves: Groves = undefined,
    a: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) Self {
        return Self{ .groves = Groves.init(a), .a = a };
    }
    pub fn deinit(self: *Self) void {
        self.parser.deinit();
        for (self.groves) |*grove|
            grove.deinit();
        self.groves.deinit();
    }

    pub fn loadGrove(self: *Self, path: []const u8, name: []const u8) !void {
        var grove = Grove.init(name, self.a);
        try grove.loadFromFolder(path);
        try self.groves.append(grove);
    }
};
