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
    is_exclusive: bool = false,
};

a: std.mem.Allocator,

cost: ?Cost = null,
order: ?Order = null,
workers: std.ArrayList(Worker) = .empty,
wbs: ?Wbs = null,
status: ?Status = null,
date: ?Date = null,

pub fn init(a: std.mem.Allocator) Self {
    return .{ .a = a };
}

pub fn deinit(self: *Self) void {
    for (self.workers.items) |worker| {
        self.a.free(worker.name);
    }
    self.workers.deinit(self.a);
}

pub fn copy(self: Self, a: std.mem.Allocator) !Self {
    var rv = Self{
        .a = a,
        .cost = self.cost,
        .order = self.order,
        .wbs = self.wbs,
        .status = self.status,
        .date = self.date,
    };
    for (self.workers.items) |worker|
        try rv.workers.append(rv.a, .{
            .name = try rv.a.dupe(u8, worker.name),
            .is_exclusive = worker.is_exclusive,
        });
    return rv;
}

pub fn update(self: *Self, src: Self) !void {
    if (self.cost == null)
        self.cost = src.cost;
    if (self.order == null)
        self.order = src.order;
    if (self.wbs == null)
        self.wbs = src.wbs;
    if (self.status == null)
        self.status = src.status;
    if (self.date == null)
        self.date = src.date;
    for (src.workers.items) |worker|
        try self.appendWorker(worker);
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
    if (self.date) |date|
        n.attr("date", date);
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

pub fn format(self: Self, w: *std.Io.Writer) !void {
    var root = rubr.naft.Node.root(w);
    defer root.deinit();
    root.has_node = true;
    self.write(&root);
}
