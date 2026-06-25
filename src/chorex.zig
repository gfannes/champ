const std = @import("std");

const amp = @import("amp.zig");

const rubr = @import("rubr.zig");
const naft = rubr.naft;

const mero = @import("mero.zig");
const filex = @import("filex.zig");
const Wbs = @import("amp/Wbs.zig");

// A Tree node that contains AMP info (both def and non-defs)
// &cleanup naming conventions
pub const Chore = struct {
    const Self = @This();

    a: std.mem.Allocator,
    node_id: usize, // Id for forest.tree
    meta: amp.Meta,

    filepath: []const u8 = &.{},

    order_offset: i32 = 0,
    order_min: i32 = std.math.maxInt(i32),
    my_cost: u32 = 0,
    child_costs: u32 = 0,

    pub fn deinit(self: *Self) void {
        self.parts.deinit();
        self.meta.deinit();
    }

    pub fn order(self: Self) i32 {
        return self.order_offset + self.order_min;
    }

    pub fn isDone(self: Self) bool {
        const status = self.meta.status orelse return false;
        return status.kind == .Done;
    }

    pub fn write(self: Self, parent: *naft.Node, maybe_ix: ?usize) void {
        var n = parent.node("Chore");
        defer n.deinit();
        if (maybe_ix) |ix|
            n.attr("ix", ix);
        n.attr("node_id", self.node_id);
        n.attr("order_offset", self.order_offset);
        n.attr("order_min", self.order_min);
        n.attr("my_cost", self.my_cost);
        n.attr("child_costs", self.child_costs);
        if (self.filepath.len > 0)
            n.attr("filepath", self.filepath);
        self.meta.write(&n);
    }

    pub fn format(self: Self, w: *std.Io.Writer) !void {
        var root = naft.Node.root(w);
        defer root.deinit();
        self.write(&root, null);
    }
};

// Keeps track of all def-amps and its string repr without the need for tree traversal
pub const Chores = struct {
    const Self = @This();
    const List = std.ArrayList(Chore);
    const TmpConcat = std.ArrayList([]const u8);

    env: rubr.Env,
    aral: std.heap.ArenaAllocator,

    list: List = .empty,

    tmp_concat: TmpConcat = .empty,

    pub fn init(env: rubr.Env) Self {
        return .{
            .env = env,
            .aral = std.heap.ArenaAllocator.init(env.a),
        };
    }
    pub fn deinit(self: *Self) void {
        self.aral.deinit();
    }

    pub fn create(self: *Self, def: *const amp.Def, node_id: usize, tree: *const mero.Tree) !?usize {
        const aa = self.aral.allocator();
        var chore = Chore{
            .a = aa,
            .node_id = node_id,
            .meta = .{ .a = aa },
        };
        try chore.meta.update(def.meta);

        if (chore.meta.cost) |cost|
            chore.my_cost = cost.value;
        if (chore.meta.order) |order|
            chore.order_min = order.value;

        // Setup chore.filepath
        var maybe_id = rubr.opt.value(node_id);
        while (maybe_id) |id| {
            const n = tree.cptr(id);
            switch (n.type) {
                .grove, .folder, .file => chore.filepath = n.filepath,
                else => {},
            }
            maybe_id = if (try tree.parent(id)) |p| p.id else null;
            if (chore.filepath.len > 0)
                // We found a filepath: stop search
                maybe_id = null;
        }

        const chore_ix = self.list.items.len;
        try self.list.append(aa, chore);

        return chore_ix;
    }

    pub fn update(self: *Self, chore_id: usize, def: *const amp.Def) !void {
        const chore = &self.list.items[chore_id];

        // Aggregate metadata from def into chore
        const is_exclusive: bool = if (chore.meta.order) |order| order.is_exclusive else false;
        if (def.meta.order) |order| {
            if (order.relative) {
                chore.order_offset += order.value;
            } else {
                if (!is_exclusive) {
                    chore.order_min = @min(chore.order_min, order.value);
                }
            }
        }
        for (def.meta.workers.items) |worker| {
            try chore.meta.appendWorker(worker);
        }

        // Aggregate metadata from chore into def
        if (def.chore_id) |other_chore_id| {
            if (chore_id != other_chore_id) {
                const other_chore = &self.list.items[other_chore_id];
                other_chore.child_costs += chore.my_cost;
            }
        }
    }

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Chores");
        defer n.deinit();
        for (self.list.items, 0..) |e, ix0| {
            e.write(&n, ix0);
        }
    }
};

test "chore" {
    var env_inst = rubr.Env.Instance{};
    env_inst.init();
    defer env_inst.deinit();

    const env = env_inst.env();

    var chores = Chores.init(env);
    defer chores.deinit();

    var tree = mero.Tree.init(env.a);
    defer tree.deinit();

    var defmgr = amp.DefMgr.init(env, "?");
    defer defmgr.deinit();

    const ch0 = try tree.addChild(null);
    ch0.data.* = mero.Node{ .a = env.a };

    const ch1 = try tree.addChild(null);
    ch1.data.* = mero.Node{ .a = env.a };

    const ch2 = try tree.addChild(null);
    ch2.data.* = mero.Node{ .a = env.a };
}
