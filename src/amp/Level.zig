const std = @import("std");

const Self = @This();

const Options = struct {};

level: i64,

pub fn parse(str: []const u8, options: Options) ?Self {
    _ = options;
    const i = std.fmt.parseInt(i64, str, 10) catch return null;
    return .{ .level = i };
}
