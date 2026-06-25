const std = @import("std");
const rubr = @import("../rubr.zig");

const Self = @This();

pub const Wbs = @import("Wbs.zig");
pub const Status = @import("Status.zig");
pub const Date = @import("Date.zig");

pub const Cost = struct {
    value: u32,
};
pub const Order = struct {
    value: i32,
    relative: bool,
    is_exclusive: bool = false,
};
pub const Worker = struct {
    name: []const u8,
};

a: std.mem.Allocator,

cost: ?Cost = null,
order: ?Order = null,
workers: std.ArrayList(Worker) = .empty,
wbs: ?Wbs = null,
status: ?Status = null,
date: ?Date = null,

pub fn deinit(self: *Self) void {
    for (self.workers.items) |worker| {
        self.a.free(worker.name);
    }
    self.workers.deinit(self.a);
}

pub fn update(self: *Self, src: Self) !void {
    self.cost = src.cost;
    self.order = src.order;
    self.wbs = src.wbs;
    self.status = src.status;
    self.date = src.date;
    try self.workers.resize(self.a, 0);
    for (src.workers.items) |worker| {
        try self.appendWorker(worker);
    }
}

pub fn hasWorker(self: Self, worker: Worker) bool {
    for (self.workers.items) |w|
        if (std.mem.eql(u8, w.name, worker.name))
            return true;
    return false;
}

pub fn appendWorker(self: *Self, worker: Worker) !void {
    if (!self.hasWorker(worker))
        try self.workers.append(self.a, Worker{ .name = try self.a.dupe(u8, worker.name) });
}

pub fn hasData(self: Self) bool {
    if (self.cost != null)
        return true;
    if (self.order != null)
        return true;
    if (self.wbs != null)
        return true;
    if (self.status != null)
        return true;
    if (self.date != null)
        return true;
    if (self.workers.items.len > 0)
        return true;
    return false;
}

pub fn write(self: Self, parent: *rubr.naft.Node) void {
    var n = parent.node("Meta");
    defer n.deinit();

    if (self.status) |status|
        n.attr("status", status.lower());
    // &todo &meta print date
    // if (self.date) |date|
    //     n.attr("date", date.lower());
    if (self.cost) |cost|
        n.attr("cost", cost.value);
    if (self.order) |order| {
        n.attr("order", order.value);
        n.attr("relative", order.relative);
        n.attr("is_exclusive", order.is_exclusive);
    }
    for (self.workers.items) |worker| {
        n.attr("worker", worker.name);
    }
    if (self.wbs) |wbs|
        n.attr("wbs", wbs.lower());
}
