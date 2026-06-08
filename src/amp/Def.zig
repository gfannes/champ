const std = @import("std");
const rubr = @import("../rubr.zig");
const Path = @import("Path.zig");
const filex = @import("../filex.zig");
const Wbs = @import("Wbs.zig");

const Self = @This();

pub const Ix = rubr.idx.Ix(@This());

pub const Location = struct {
    grove_id: usize,
    path: []const u8,
    node_id: usize,
    pos: filex.Pos,
};

ap: Path,
location: ?Location = null,
template: ?Ix = null,

kind: ?Wbs.Kind = null,
prio: ?i32 = null,

pub fn deinit(self: *Self) void {
    self.ap.deinit();
}

pub fn write(self: Self, parent: *rubr.naft.Node, maybe_ix: ?usize) void {
    var n = parent.node("Def");
    defer n.deinit();
    if (maybe_ix) |ix|
        n.attr("ix", ix);
    n.attr("ap", self.ap);
    if (self.location) |loc| {
        n.attr("grove_id", loc.grove_id);
        n.attr("path", loc.path);
        n.attr("row", loc.pos.row);
        n.attr("cols.begin", loc.pos.cols.begin);
        n.attr("cols.end", loc.pos.cols.end);
    }
    if (self.kind) |kind|
        n.attr("kind", kind);
    if (self.prio) |prio|
        n.attr("prio", prio);
}
pub fn format(self: Self, w: *std.Io.Writer) !void {
    var r = rubr.naft.Node.root(w);
    defer r.deinit();
    self.write(&r, null);
}
