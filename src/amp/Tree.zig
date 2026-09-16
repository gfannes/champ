const std = @import("std");

const Node = @import("Node.zig");
const Path = @import("Path.zig");

const rubr = @import("../rubr.zig");
const filex = @import("../filex.zig");

const Self = @This();
const Tree = rubr.tree.Tree(Node);

a: std.mem.Allocator,
tree: Tree,
root: Tree.Entry = undefined,
phony: Tree.Entry = undefined,

pub fn init(a: std.mem.Allocator) !Self {
    var rv: Self = .{
        .a = a,
        .tree = .init(a),
    };
    rv.root = try rv.tree.addChild(null);
    rv.root.data.* = .{ .name = "<ROOT>" };

    rv.phony = try rv.tree.addChild(null);
    rv.phony.data.* = .{ .name = "<PHONY>" };
    return rv;
}
pub fn deinit(self: *Self) void {
    self.tree.deinit();
}

pub fn addAbsolute(self: *Self, ap: Path, grove_id: usize, dto_id: usize, filepath: []const u8, pos: filex.Pos) !usize {
    _ = grove_id;

    var parent = self.root.id;
    for (ap.parts.items) |part| {
        var maybe_child_id: ?usize = null;
        for (self.tree.childIds(parent)) |child_id| {
            const n = self.tree.cptr(child_id);
            if (std.mem.eql(u8, part.content, n.name orelse "")) {
                maybe_child_id = child_id;
            }
        }
        if (maybe_child_id) |child_id| {
            // Found match: continue the search
            parent = child_id;
        } else {
            // No match found: insert new node
            const entry = try self.tree.addChild(parent);
            parent = entry.id;
            entry.data.* = .{ .name = part.content, .node_id = dto_id, .filepath = filepath, .pos = pos };
        }
    }

    return parent;
}

pub fn addUnnamed(self: *Self, parent_id: usize, dto_id: usize, filepath: []const u8, pos: filex.Pos) !usize {
    const entry = try self.tree.addChild(parent_id);
    entry.data.* = .{ .node_id = dto_id, .filepath = filepath, .pos = pos };
    return entry.id;
}

pub fn format(self: Self, w: *std.Io.Writer) !void {
    for (self.tree.root_ids.items) |root_id| {
        try self.format_(w, root_id, 0);
    }
}
fn format_(self: Self, w: *std.Io.Writer, id: usize, depth: usize) !void {
    for (0..depth) |_|
        try w.print("  ", .{});

    try w.print("{f}", .{self.tree.cptr(id).*});

    for (self.tree.childIds(id)) |child_id| {
        try self.format_(w, child_id, depth + 1);
    }
}

test "amp.Tree" {
    const ut = std.testing;

    var tree = try Self.init(ut.allocator);
    defer tree.deinit();

    (try tree.tree.addChild(tree.root.id)).data.* = .{ .name = "A" };
    (try tree.tree.addChild(tree.root.id)).data.* = .{ .name = "B" };
    (try tree.tree.addChild(tree.root.id)).data.* = .{ .name = "C" };

    std.debug.print("{f}", .{tree});

    try ut.expect(true);
}
