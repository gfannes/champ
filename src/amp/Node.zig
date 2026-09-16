const std = @import("std");

const filex = @import("../filex.zig");

const Self = @This();

name: ?[]const u8 = null,
node_id: ?usize = null,
filepath: []const u8 = &.{},
pos: filex.Pos = .{},

pub fn format(self: Self, w: *std.Io.Writer) !void {
    try w.print("{?s} {?} {s}:{}\n", .{ self.name, self.node_id, self.filepath, self.pos.row });
}
