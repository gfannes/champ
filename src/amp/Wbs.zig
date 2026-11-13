const std = @import("std");
const rubr = @import("../rubr.zig");

const Self = @This();

const Options = struct {};

pub const Kind = enum(u3) { Task, Story, Epic, Area, Project, Program, Portfolio };

kind: Kind,
prio: ?i32 = null,

pub fn lower(self: Self) []const u8 {
    switch (self.kind) {
        .Portfolio => return "portfolio",
        .Program => return "program",
        .Project => return "project",
        .Area => return "area",
        .Epic => return "epic",
        .Story => return "story",
        .Task => return "task",
    }
}

pub fn compare(self: Self, other: Self) std.math.Order {
    return std.math.order(@backingInt(self.kind), @backingInt(other.kind));
}

pub fn parse(strange: *rubr.strng.Strange, options: Options) ?Self {
    _ = options;
    var maybe_sp: ?rubr.strng.Strange = strange.*;
    defer {
        if (maybe_sp) |sp| strange.* = sp;
    }

    var res: ?Self = null;

    if (strange.popStr("portfolio")) {
        res = .{ .kind = .Portfolio };
    } else if (strange.popStr("program")) {
        res = .{ .kind = .Program };
    } else if (strange.popStr("project")) {
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

    maybe_sp = null;
    return res;
}

pub fn write(self: Self, parent: *rubr.naft.Node) void {
    var node = parent.node("Wbs");
    defer node.deinit();

    node.attr("kind", self.kind);
    if (self.prio) |prio|
        node.attr("prio", prio);
}
pub fn format(self: Self, w: *std.Io.Writer) !void {
    rubr.naft.Node.write(self, w);
}
