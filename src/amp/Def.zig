const std = @import("std");
const rubr = @import("../rubr.zig");
const Path = @import("Path.zig");
const filex = @import("../filex.zig");
const Wbs = @import("Wbs.zig");
const Status = @import("Status.zig");
const Date = @import("Date.zig");

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
chore_id: ?usize = null,

status: ?Status = null,
cost: ?Path.Cost = null,
order: ?Path.Order = null,
worker: ?Path.Worker = null,
wbs: ?Wbs = null,
date: ?Date = null,

pub fn deinit(self: *Self) void {
    self.ap.deinit();
}

pub fn injectMeta(self: *Self, ap: Path) !void {
    if (!ap.isMeta())
        return error.ExpectedMetaPath;
    switch (ap.parts.items[0].meta.?) {
        .status => |status| self.status = status,
        .cost => |cost| self.cost = cost,
        .order => |order| self.order = order,
        .worker => |worker| self.worker = worker,
        .wbs => |wbs| self.wbs = wbs,
        .date => |date| self.date = date,
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
    if (self.status) |status|
        n.attr("status", status.lower());
    // &todo &meta print date
    // if (self.date) |date|
    //     n.attr("date", date.lower());
    if (self.cost) |cost|
        n.attr("cost", cost.value);
    if (self.order) |order|
        n.attr("order", order.value);
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
