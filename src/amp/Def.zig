const std = @import("std");
const rubr = @import("../rubr.zig");
const filex = @import("../filex.zig");
const Path = @import("Path.zig");
const Meta = @import("Meta.zig");
const Wbs = @import("Wbs.zig");
const Status = @import("Status.zig");
const Date = @import("Date.zig");

const Error = error{
    ExpectedMetaPath,
};

const Self = @This();

pub const Ix = rubr.idx.Ix(@This());

pub const Location = struct {
    filepath: []const u8,
    node_id: usize,
    pos: filex.Pos,
};

path: Path,
meta: Meta,
grove_id: usize,

location: ?Location = null,
chore_id: ?usize = null,

pub fn deinit(self: *Self) void {
    self.path.deinit();
    self.meta.deinit();
}

pub fn write(self: Self, parent: *rubr.naft.Node, maybe_ix: ?usize) void {
    var n = parent.node("Def");
    defer n.deinit();
    if (maybe_ix) |ix|
        n.attr("ix", ix);
    n.attr("path", self.path);
    if (self.chore_id) |chore_id|
        n.attr("chore_id", chore_id);
    n.attr("grove_id", self.grove_id);
    if (self.location) |loc| {
        n.attr("node_id", loc.node_id);
        n.attr("filepath", loc.filepath);
        n.attr("row", loc.pos.row);
        n.attr("cols.begin", loc.pos.cols.begin);
        n.attr("cols.end", loc.pos.cols.end);
    }
    self.meta.write(&n);
}
pub fn format(self: Self, w: *std.Io.Writer) !void {
    var r = rubr.naft.Node.root(w);
    defer r.deinit();
    self.write(&r, null);
}
