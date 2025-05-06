const std = @import("std");

const mero = @import("mero.zig");

pub const Chore = struct {
    const Self = @This();

    node_id: usize,
    def: []const u8 = &.{},

    pub fn init(node_id: usize) Self {
        return Self{ .node_id = node_id };
    }
    pub fn deinit(self: *Self) void {
        _ = self;
    }
};

pub const ChoreList = struct {
    const Self = @This();
    const List = std.ArrayList(Chore);

    list: List,
    aa: std.heap.ArenaAllocator,

    pub fn init(a: std.mem.Allocator) Self {
        return Self{
            // Do not use the arena allocator since Self will still be moved
            .list = List.init(a),
            .aa = std.heap.ArenaAllocator.init(a),
        };
    }
    pub fn deinit(self: *Self) void {
        self.aa.deinit();
        self.list.deinit();
    }

    pub fn add(self: *Self, node_id: usize) !void {
        var chore = Chore{ .node_id = node_id };

        const aaa = self.aa.allocator();
        chore.def = try aaa.dupe(u8, "test123");

        try self.list.append(chore);
    }
};

test "chore" {
    const ut = std.testing;

    var cl = ChoreList.init(ut.allocator);
    defer cl.deinit();

    try cl.add(0);
    try cl.add(1);
    try cl.add(2);
}
