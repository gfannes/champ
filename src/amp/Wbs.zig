const std = @import("std");
const rubr = @import("../rubr.zig");

const Self = @This();

const Options = struct {};

pub const Kind = enum { Project, Area, Epic, Story, Task };

kind: Kind,
prio: ?i32 = null,

pub fn parse(str: []const u8, options: Options) ?Self {
    _ = options;

    var res: ?Self = null;

    var strange = rubr.strng.Strange{ .content = str };
    if (strange.popStr("project")) {
        res = .{ .kind = .Project };
    } else if (strange.popStr("area")) {
        res = .{ .kind = .Area };
    } else if (strange.popStr("epic")) {
        res = .{ .kind = .Epic };
    } else if (strange.popStr("story")) {
        res = .{ .kind = .Story };
    } else if (strange.popStr("task")) {
        res = .{ .kind = .Task };
    } else {
        return null;
    }

    if (strange.popChar('=')) {
        if (strange.popInt(i32)) |v|
            res.?.prio = v;
    }

    return res;
}
