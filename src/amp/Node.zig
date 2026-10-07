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
    pub const Kind = enum {
        Definition,
        Implicit,
        Reference,
    };

    kind: Kind,
    path: []const u8 = &.{},
    pos: filex.Pos,
    mero_id: usize,
    grove_id: usize,

    pub fn write(self: @This(), parent: *rubr.naft.Node) void {
        var n = parent.node("Location");
        defer n.deinit();
        const kind = switch (self.kind) {
            .Definition => "def",
            .Implicit => "implicit",
            .Reference => "ref",
        };
        n.attr("kind", kind);
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

// Checks the first location kind
pub fn isKind(self: Self, kind: Location.Kind) bool {
    if (rubr.slc.first(self.locations.items)) |loc|
        return loc.kind == kind;
    return false;
}

pub fn definedInGrove(self: Self, grove_id: usize) bool {
    for (self.locations.items[0..self.def_count]) |location| {
        if (location.grove_id == grove_id)
            return true;
    }
    return false;
}

pub fn appendLocation(self: *Self, location: Location) !void {
    if (location.kind == .Definition and self.locations.items.len > 0 and self.locations.items[0].kind == .Implicit) {
        // This location is already present as an Implicit one (created as part of the base of a path).
        // We _replace_ it with this Definition.
        self.locations.items[0] = location;
    } else {
        if (location.kind == .Definition or location.kind == .Implicit) {
            if (self.def_count != self.locations.items.len)
                return error.FoundDefinitionAfterReference;
            self.def_count += 1;
        }
        try self.locations.append(self.a, location);
    }
}

pub fn aggregate(self: *Self, other: *Self) !void {
    // Aggregate metadata from other into self
    if (other.meta) |other_meta| {
        if (other_meta.hasData()) {
            if (self.meta == null)
                // Do not inherit metadata here, inheritance works via the ancestor dependencies
                self.meta = Meta.init(self.a);

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

                // &node:sort: We track the smallest date when present since this has highest prio
                if (other_meta.date) |other_date| {
                    if (self.date_min) |date_min| {
                        if (other_date.date.epoch_day.day < date_min.date.epoch_day.day)
                            self.date_min = other_date;
                    } else {
                        // This Node has no date yet: inherit from other
                        self.date_min = other_date;
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

pub fn updateMeta(self: *Self, meta: Meta) !void {
    if (!meta.hasData())
        return;

    if (self.meta) |*my_meta| {
        try my_meta.update(meta);
    } else {
        self.meta = try meta.copy(self.a);
    }

    if (meta.cost) |cost|
        self.my_cost += cost.value;
    if (meta.order) |ordr| {
        self.order_min = @min(self.order_min, ordr.value);
        if (ordr.is_exclusive)
            self.order_min_locked = true;
    }
    if (meta.date) |meta_date| {
        if (self.date_min) |date_min| {
            if (meta_date.date.epoch_day.day < date_min.date.epoch_day.day)
                self.date_min = meta_date;
        } else {
            // This Node has no date yet: inherit from other
            self.date_min = meta_date;
        }
    }
}

pub fn write(self: Self, parent: *rubr.naft.Node) void {
    var n = parent.node("Node");
    defer n.deinit();

    if (self.name) |name|
        n.attr("name", name);

    if (self.meta) |meta|
        meta.write(&n);
    for (self.locations.items) |location| {
        location.write(&n);
    }
}

pub fn format(self: Self, w: *std.Io.Writer) !void {
    rubr.naft.Node.write(self, w);
}
