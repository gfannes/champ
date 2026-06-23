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
    grove_id: usize,
    filepath: []const u8,
    node_id: usize,
    pos: filex.Pos,
};

ap: Path,
meta: Meta,

location: ?Location = null,
chore_id: ?usize = null,

pub fn deinit(self: *Self) void {
    self.ap.deinit();
    self.meta.deinit();
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
    if (self.location) |loc| {
        n.attr("grove_id", loc.grove_id);
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
