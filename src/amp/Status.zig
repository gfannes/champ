const rubr = @import("rubr");

const Self = @This();

// Capital status spelling, similar to [todo-comments](https://github.com/folke/todo-comments.nvim)
const capitals = [_][]const u8{ "TODO", "NEXT", "WIP", "DONE", "QUESTION", "CALLOUT", "FORWARD", "CANCELED" };
// Lower-case variant. Infinite lifetime is important: amp.Path.Part blindly assumes its content lives long enough.
const lowers = [_][]const u8{ "todo", "next", "wip", "done", "question", "callout", "forward", "canceled" };

pub const Kind = enum(usize) {
    Todo,
    Next,
    Wip,
    Done,
    Question,
    Callout,
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
