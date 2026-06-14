const std = @import("std");
const rubr = @import("../rubr.zig");
const Path = @import("Path.zig");
const filex = @import("../filex.zig");
const Wbs = @import("Wbs.zig");

const Error = error{
    ExpectedMetaPath,
};

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
chore_id: ?usize = null,

cost: ?Path.Cost = null,
prio: ?Path.Pri = null,
worker: ?Path.Worker = null,
wbs: ?Wbs = null,

pub fn deinit(self: *Self) void {
    self.ap.deinit();
}

pub fn injectMeta(self: *Self, ap: Path) !void {
    if (!ap.isMeta())
        return error.ExpectedMetaPath;
    switch (ap.parts.items[0].meta.?) {
        .cost => |cost| self.cost = cost,
        .prio => |prio| self.prio = prio,
        .worker => |worker| self.worker = worker,
        .wbs => |wbs| self.wbs = wbs,
        else => {},
    }
}

pub fn write(self: Self, parent: *rubr.naft.Node, maybe_ix: ?usize) void {
    var n = parent.node("Def");
    defer n.deinit();
    if (maybe_ix) |ix|
        n.attr("ix", ix);
    n.attr("ap", self.ap);
    if (self.chore_id) |chore_id|
        n.attr("chore_id", chore_id);
    if (self.cost) |cost|
        n.attr("cost", cost.value);
    if (self.prio) |prio|
        n.attr("prio", prio.value);
    if (self.worker) |worker|
        n.attr("worker", worker.name);
    if (self.wbs) |wbs|
        n.attr("wbs", wbs.lower());
    if (self.location) |loc| {
        n.attr("grove_id", loc.grove_id);
        n.attr("path", loc.path);
        n.attr("row", loc.pos.row);
        n.attr("cols.begin", loc.pos.cols.begin);
        n.attr("cols.end", loc.pos.cols.end);
    }
}
pub fn format(self: Self, w: *std.Io.Writer) !void {
    var r = rubr.naft.Node.root(w);
    defer r.deinit();
    self.write(&r, null);
}
