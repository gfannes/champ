const std = @import("std");

const rubr = @import("rubr");
const naft = rubr.naft;

const mero = @import("mero.zig");

pub const Chore = struct {
    const Self = @This();

    node_id: usize,
    str: []const u8 = &.{},
    path: []const u8 = &.{},

    pub fn init(node_id: usize) Self {
        return Self{ .node_id = node_id };
    }
    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Chore");
        defer n.deinit();
        n.attr("id", self.node_id);
        if (self.str.len > 0)
            n.attr("str", self.str);
        if (self.path.len > 0)
            n.attr("path", self.path);
    }
};

pub const ChoreList = struct {
    const Self = @This();
    const List = std.ArrayList(Chore);
    const Tmp = std.ArrayList([]const u8);

    list: List,
    aa: std.heap.ArenaAllocator,
    tmp: Tmp,

    pub fn init(a: std.mem.Allocator) Self {
        return Self{
            // Do not use the arena allocator since Self will still be moved
            .list = List.init(a),
            .aa = std.heap.ArenaAllocator.init(a),
            .tmp = Tmp.init(a),
        };
    }
    pub fn deinit(self: *Self) void {
        self.aa.deinit();
        self.list.deinit();
        self.tmp.deinit();
    }

    // Return true if tree[node_id] is an actual Chore and was thus added
    pub fn add(self: *Self, node_id: usize, tree: mero.Tree) !bool {
        const node = tree.cptr(node_id);

        const aaa = self.aa.allocator();

        try self.tmp.resize(0);
        var sep: []const u8 = "";
        for (node.orgs.items) |org| {
            try self.tmp.append(try std.fmt.allocPrint(aaa, "{s}{}", .{ sep, org }));
            sep = " ";
        }

        if (self.tmp.items.len == 0)
            // This is not a Chore
            return false;

        var chore = Chore{ .node_id = node_id };
        chore.str = try std.mem.concat(aaa, u8, self.tmp.items);

        var maybe_id = rubr.opt.value(node_id);
        while (maybe_id) |id| {
            const n = tree.cptr(id);
            switch (n.type) {
                mero.Node.Type.Folder => chore.path = n.path,
                mero.Node.Type.File => chore.path = n.path,
                else => {},
            }
            if (try tree.parent(id)) |p|
                maybe_id = p.id;
            if (chore.path.len > 0)
                maybe_id = null;
        }

        try self.list.append(chore);

        return true;
    }

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("ChoreList");
        defer n.deinit();
        n.attr("count", self.list.items.len);
        for (self.list.items) |chore| {
            chore.write(&n);
        }
    }
};

test "chore" {
    const ut = std.testing;

    var cl = ChoreList.init(ut.allocator);
    defer cl.deinit();

    var tree = mero.Tree.init(ut.allocator);
    defer tree.deinit();

    const ch0 = try tree.addChild(null);
    ch0.data.* = mero.Node.init(ut.allocator);

    const ch1 = try tree.addChild(null);
    ch1.data.* = mero.Node.init(ut.allocator);

    const ch2 = try tree.addChild(null);
    ch2.data.* = mero.Node.init(ut.allocator);

    _ = try cl.add(0, tree);
    _ = try cl.add(1, tree);
    _ = try cl.add(2, tree);
}
