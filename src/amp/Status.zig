const std = @import("std");
const rubr = @import("rubr");

const Self = @This();

// Capital status spelling, similar to [todo-comments](https://github.com/folke/todo-comments.nvim)
const capitals = [_][]const u8{ "TODO", "NEXT", "WIP", "DONE", "QUESTION", "INFO", "BLOCKED", "FORWARD", "CANCELED" };
// Lower-case variant. Infinite lifetime is important: amp.Path.Part blindly assumes its content lives long enough.
const lowers = [_][]const u8{ "todo", "next", "wip", "done", "question", "info", "blocked", "forward", "canceled" };

pub const Kind = enum(usize) {
    Todo,
    Next,
    Wip,
    Done,
    Question,
    Info,
    Blocked,
    Forward,
    Canceled,
};

kind: Kind,

pub fn fromLower(str: []const u8) ?Self {
    if (rubr.strings.index(u8, &lowers, str)) |ix0|
        return Self{ .kind = @enumFromInt(ix0) };
    return null;
}
pub fn fromCapital(str: []const u8) ?Self {
    if (rubr.strings.index(u8, &capitals, str)) |ix0|
        return Self{ .kind = @enumFromInt(ix0) };
    return null;
}

pub fn lower(self: Self) []const u8 {
    return lowers[@intFromEnum(self.kind)];
}

test "amp.Status.fromLower" {
    const ut = std.testing;
    try ut.expectEqual(Self{ .kind = .Todo }, fromLower("todo"));
    try ut.expectEqual(Self{ .kind = .Canceled }, fromLower("canceled"));
    try ut.expectEqual(null, fromLower("TODO"));
    try ut.expectEqual(null, fromLower("CANCELED"));
}
test "amp.Status.fromCapital" {
    const ut = std.testing;
    try ut.expectEqual(Self{ .kind = .Todo }, fromCapital("TODO"));
    try ut.expectEqual(Self{ .kind = .Canceled }, fromCapital("CANCELED"));
    try ut.expectEqual(null, fromCapital("todo"));
    try ut.expectEqual(null, fromCapital("canceled"));
}
test "amp.Status.lower" {
    const ut = std.testing;
    try ut.expectEqualStrings("todo", lower(.{ .kind = .Todo }));
    try ut.expectEqualStrings("canceled", lower(.{ .kind = .Canceled }));
}
