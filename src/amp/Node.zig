const std = @import("std");

const Meta = @import("Meta.zig");
const Date = @import("Date.zig");

const filex = @import("../filex.zig");
const rubr = @import("../rubr.zig");

const Self = @This();

pub const Error = error{
    FoundDefinitionAfterReference,
};

pub const Location = struct {
    path: []const u8 = &.{},
    pos: filex.Pos,
    mero_id: usize,
    grove_id: usize,

    pub fn write(self: @This(), parent: *rubr.naft.Node, typ: []const u8) void {
        var n = parent.node("Location");
        defer n.deinit();
        n.attr("type", typ);
        n.attr("grove_id", self.grove_id);
        n.attr("row", self.pos.row);
        n.attr("mero_id", self.mero_id);
        n.attr("path", self.path);
    }
};

a: std.mem.Allocator,
name: ?[]const u8 = null,
locations: std.ArrayList(Location) = .empty,
def_count: usize = 0,
ancestors: std.ArrayList(usize) = .empty,
direct_ancestor_count: usize = 0,
meta: ?Meta = null,

order_offset: i32 = 0,
order_min: i32 = std.math.maxInt(i32),
order_min_locked: bool = false,
my_cost: u32 = 0,
child_costs: u32 = 0,
date_min: ?Date = null,

pub fn init(self: *Self, a: std.mem.Allocator, name: ?[]const u8) void {
    self.* = .{
        .a = a,
        .name = name,
    };
}

pub fn deinit(self: *Self) void {
    self.locations.deinit(self.a);
    self.ancestors.deinit(self.a);
    if (self.meta) |*meta|
        meta.deinit();
}

pub fn isDone(self: Self) bool {
    const meta = self.meta orelse return false;
    const status = meta.status orelse return false;
    return status.kind == .Done;
}

pub fn order(self: Self) i32 {
    return self.order_offset + self.order_min;
}

pub const Where = enum { Definition, Reference };
pub fn appendLocation(self: *Self, where: Where, grove_id: usize, filepath: []const u8, pos: filex.Pos, mero_id: usize) !void {
    if (where == .Definition) {
        if (self.def_count != self.locations.items.len)
            return error.FoundDefinitionAfterReference;
        self.def_count += 1;
    }
    try self.locations.append(self.a, .{ .path = filepath, .pos = pos, .mero_id = mero_id, .grove_id = grove_id });
}

pub fn aggregate(self: *Self, other: *Self) !void {
    // Aggregate metadata from other into self
    if (other.meta) |other_meta| {
        if (other_meta.hasData()) {
            if (self.meta == null)
                self.meta = try other_meta.copy(self.a);

            if (self.meta) |*self_meta| {
                if (other_meta.order) |ordr| {
                    if (ordr.relative) {
                        self.order_offset += ordr.value;
                    } else {
                        if (!self.order_min_locked) {
                            self.order_min = @min(self.order_min, ordr.value);
                            self.order_min_locked = ordr.is_exclusive;
                        }
                    }
                }
                for (other_meta.workers.items) |worker| {
                    try self_meta.appendWorker(worker);
                }

                // &chore:sort: We track the smallest date when present since this has highest prio
                if (other_meta.date) |date| {
                    if (self.date_min) |date_min| {
                        if (date.date.epoch_day.day < date_min.date.epoch_day.day)
                            self.date_min = date;
                    } else {
                        // This Chore has no date yet: inherit from def
                        self.date_min = date;
                    }
                }
            }
        }
    }

    // Aggregate metadata from self into other
    if (self != other) {
        other.child_costs += self.my_cost;
    }
}

pub fn setMeta(self: *Self, meta: Meta) !void {
    if (!meta.hasData())
        return;
    self.meta = try meta.copy(self.a);

    if (self.meta) |self_meta| {
        if (self_meta.cost) |cost|
            self.my_cost = cost.value;
        if (self_meta.order) |ordr| {
            self.order_min = ordr.value;
            self.order_min_locked = ordr.is_exclusive;
        }
        self.date_min = self_meta.date;
    }
}

pub fn write(self: Self, parent: *rubr.naft.Node) void {
    var n = parent.node("Node");
    defer n.deinit();

    if (self.name) |name|
        n.attr("name", name);

    self.meta.write(&n);
    for (self.locations.items, 0..) |location, ix0| {
        location.write(&n, if (ix0 < self.def_count) "def" else "ref");
    }
}

pub fn format(self: Self, w: *std.Io.Writer) !void {
    rubr.naft.Node.write(self, w);
}
