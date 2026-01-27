const std = @import("std");

const Self = @This();

const Options = struct {};

pub const Kind = enum { Project, Area, Epic, Story, Task };

kind: Kind,

pub fn parse(str: []const u8, options: Options) ?Self {
    _ = options;
    if (std.mem.eql(u8, str, "project")) {
        return .{ .kind = .Project };
    } else if (std.mem.eql(u8, str, "area")) {
        return .{ .kind = .Area };
    } else if (std.mem.eql(u8, str, "epic")) {
        return .{ .kind = .Epic };
    } else if (std.mem.eql(u8, str, "story")) {
        return .{ .kind = .Story };
    } else if (std.mem.eql(u8, str, "task")) {
        return .{ .kind = .Task };
    }
    return null;
}
