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
    for (self.tree.nodes.items) |*node| {
        self.a.free(node.data.locations);
        node.data.dependencies.deinit(self.a);
    }
    self.tree.deinit();
}

pub fn addAbsolute(self: *Self, ap: Path, grove_id: usize, dto_id: usize, filepath: []const u8, pos: filex.Pos) !usize {
    return try self.addAbsolute_(self.root.id, ap, grove_id, dto_id, filepath, pos);
}

pub fn addPhony(self: *Self, ap: Path, grove_id: usize, dto_id: usize, filepath: []const u8, pos: filex.Pos) !usize {
    return try self.addAbsolute_(self.phony.id, ap, grove_id, dto_id, filepath, pos);
}

fn addAbsolute_(self: *Self, node_id: usize, ap: Path, grove_id: usize, dto_id: usize, filepath: []const u8, pos: filex.Pos) !usize {
    _ = grove_id;

    var parent = node_id;
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
            const locations = try self.a.alloc(Node.Location, 1);
            locations[0] = .{ .path = filepath, .pos = pos, .dto_id = dto_id };
            entry.data.* = .{ .name = part.content, .locations = locations };
        }
    }

    return parent;
}

pub fn addUnnamed(self: *Self, maybe_parent_id: ?usize, dto_id: usize, filepath: []const u8, pos: filex.Pos) !usize {
    const parent_id = maybe_parent_id orelse self.root.id;

    const entry = try self.tree.addChild(parent_id);
    const locations = try self.a.alloc(Node.Location, 1);
    locations[0] = .{ .path = filepath, .pos = pos, .dto_id = dto_id };
    entry.data.* = .{ .locations = locations };
    return entry.id;
}

pub fn resolve(self: *Self, ap: Path) !?usize {
    var cb = struct {
        const My = @This();
        ap: Path,
        tree: *Tree,
        depth: usize = 0,
        found_id: ?usize = null,
        pub fn call(my: *My, entry: Tree.Entry, before: bool) !void {
            if (before) {
                my.depth += 1;
                if (my.isFit(entry)) {
                    // &todo: handle ambiguous matches
                    my.found_id = entry.id;
                }
            } else {
                my.depth -= 1;
            }
        }

        fn isFit(my: My, leaf: Tree.Entry) bool {
            const part_count = my.ap.parts.items.len;
            if (my.depth < part_count)
                return false;

            var entry = leaf;
            for (0..part_count) |ix0| {
                const part = my.ap.parts.items[part_count - 1 - ix0];
                const name = entry.data.name orelse return false;
                // std.log.debug("Comparing {s} with {s}", .{ part.content, name });
                if (!std.mem.eql(u8, part.content, name))
                    return false;
                entry = (my.tree.parent(entry.id) catch return false) orelse return false;
            }
            return true;
        }
    }{ .ap = ap, .tree = &self.tree };
    try self.tree.dfs(self.root.id, &cb);
    return cb.found_id;
}

pub fn addDependency(self: *Self, from: usize, to: usize) !bool {
    if (from == to)
        // No self-dependencies
        return false;

    const node = self.tree.ptr(from);
    var deps = &node.dependencies;
    for (deps.items) |dep|
        if (dep == to)
            return false;
    try deps.append(self.a, to);
    return true;
}

pub fn addAncestralDependencies(self: *Self) !void {
    var cb = struct {
        const My = @This();
        outer: *Self,
        pub fn call(my: *My, entry: Tree.Entry, before: bool) !void {
            if (!before)
                return;
            if (try my.outer.tree.parent(entry.id)) |parent|
                _ = try my.outer.addDependency(parent.id, entry.id);
        }
    }{ .outer = self };
    try self.tree.dfsAll(&cb);
}

pub fn aggregateDependencies(self: *Self) !void {
    var cb = struct {
        const My = @This();
        new_dep_count: u64 = 0,
        outer: *Self,
        pub fn call(my: *My, entry: Tree.Entry, before: bool) !void {
            if (!before)
                return;

            // Do not directly iterate on items since addDependencies() might reallocate that
            for (0..entry.data.dependencies.items.len) |ix0| {
                const dep = entry.data.dependencies.items[ix0];
                for (my.outer.tree.cptr(dep).dependencies.items) |depp| {
                    if (try my.outer.addDependency(entry.id, depp))
                        my.new_dep_count += 1;
                }
            }
        }
    }{ .outer = self };

    while (true) {
        cb.new_dep_count = 0;
        try self.tree.dfsAll(&cb);
        if (cb.new_dep_count == 0)
            break;
        std.log.info("Found {} new dependencies, aggregating again", .{cb.new_dep_count});
    }
}

pub fn write(self: Self, parent: *rubr.naft.Node) void {
    var n = parent.node("Tree");
    defer n.deinit();

    for (self.tree.root_ids.items) |root_id| {
        try self.write_(&n, root_id);
    }
}
fn write_(self: Self, parent: *rubr.naft.Node, id: usize) !void {
    var n = parent.node("Node");
    defer n.deinit();

    n.attr("id", id);

    const node = self.tree.cptr(id).*;
    if (node.name) |name|
        n.attr("name", name);
    for (node.dependencies.items) |dep|
        n.attr("dep", dep);
    for (node.locations) |location|
        location.write(&n);

    for (self.tree.childIds(id)) |child_id| {
        try self.write_(&n, child_id);
    }
}

pub fn format(self: Self, w: *std.Io.Writer) !void {
    rubr.naft.Node.write(self, w);
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
