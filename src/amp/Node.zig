const std = @import("std");

const filex = @import("../filex.zig");
const rubr = @import("../rubr.zig");

const Self = @This();

pub const Location = struct {
    path: []const u8 = &.{},
    pos: ?filex.Pos = null,
    dto_id: ?usize = null,

    pub fn write(self: @This(), parent: *rubr.naft.Node) void {
        var n = parent.node("Location");
        defer n.deinit();
        n.attr("path", self.path);
        if (self.pos) |pos|
            n.attr("row", pos.row);
        if (self.dto_id) |dto_id|
            n.attr("dto_id", dto_id);
    }
};

name: ?[]const u8 = null,
locations: []Location = &.{},
dependencies: std.ArrayList(usize) = .empty,

pub fn write(self: Self, parent: *rubr.naft.Node) void {
    var n = parent.node("Node");
    defer n.deinit();
    if (self.name) |name|
        n.attr("name", name);

    for (self.locations) |location| {
        location.write(&n);
    }
}

pub fn format(self: Self, w: *std.Io.Writer) !void {
    rubr.naft.Node.write(self, w);
}
