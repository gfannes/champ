const std = @import("std");

const Node = @import("Node.zig");
const Path = @import("Path.zig");
const Meta = @import("Meta.zig");
const mero = @import("../mero.zig");

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
    rv.root.data.init(a, "<ROOT>");

    rv.phony = try rv.tree.addChild(null);
    rv.phony.data.init(a, "<PHONY>");
    return rv;
}
pub fn deinit(self: *Self) void {
    for (self.tree.nodes.items) |*node|
        node.data.deinit();
    self.tree.deinit();
}

pub fn ampPath(self: Self, a: std.mem.Allocator, id: Tree.Id) !Path {
    var rv = Path.init(a);
    try self.ampPath_(&rv, id);
    return rv;
}
fn ampPath_(self: Self, ap: *Path, id: Tree.Id) !void {
    if (try self.tree.parent(id)) |parent| {
        if (parent.id != self.root.id and parent.id != self.phony.id)
            try self.ampPath_(ap, parent.id);
        if (self.tree.cptr(id).name) |name|
            try ap.parts.append(ap.a, .{ .content = name });
    }
}

pub fn addAbsolute(self: *Self, ap: Path, grove_id: usize, mero_id: mero.Tree.Id, filepath: []const u8, pos: filex.Pos) !Tree.Id {
    const leaf_id = try self.addAbsolute_(self.root.id, ap);

    var location: Node.Location = .{ .kind = .Definition, .grove_id = grove_id, .path = filepath, .mero_id = mero_id, .pos = pos };

    try self.tree.ptr(leaf_id).appendLocation(location);

    location.kind = .Implicit;
    var id = leaf_id;
    while (try self.tree.parent(id)) |parent| {
        id = parent.id;
        const n = self.tree.ptr(id);
        if (n.locations.items.len == 0)
            try n.appendLocation(location);
    }

    return leaf_id;
}

pub fn addPhony(self: *Self, ap: Path) !Tree.Id {
    return try self.addAbsolute_(self.phony.id, ap);
}

fn addAbsolute_(self: *Self, root_node_id: Tree.Id, ap: Path) !Tree.Id {
    var parent = root_node_id;
    for (ap.parts.items) |part| {
        var maybe_child_id: ?Tree.Id = null;
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
            entry.data.init(self.a, part.content);

            parent = entry.id;
        }
    }

    return parent;
}

pub fn addUnnamed(self: *Self, maybe_parent_id: ?Tree.Id, grove_id: usize, mero_id: mero.Tree.Id, filepath: []const u8, pos: filex.Pos) !Tree.Id {
    const parent_id = maybe_parent_id orelse self.root.id;

    const entry = try self.tree.addChild(parent_id);
    entry.data.init(self.a, null);

    try entry.data.appendLocation(.{ .kind = .Definition, .grove_id = grove_id, .path = filepath, .mero_id = mero_id, .pos = pos });

    return entry.id;
}

pub fn addReference(self: *Self, id: Tree.Id, grove_id: usize, mero_id: mero.Tree.Id, filepath: []const u8, pos: filex.Pos) !void {
    try self.tree.ptr(id).appendLocation(.{ .kind = .Reference, .grove_id = grove_id, .path = filepath, .mero_id = mero_id, .pos = pos });
}

pub fn resolve(self: *Self, ap: Path) !?Tree.Id {
    var cb = struct {
        const My = @This();
        ap: Path,
        depth: usize = 0,
        found_entry: ?Tree.Entry = null,
        outer: *Self,
        pub fn call(my: *My, entry: Tree.Entry, before: bool) !void {
            if (before) {
                my.depth += 1;
                if (my.isFit(entry)) {
                    if (my.found_entry) |found_entry| {
                        if (found_entry.data.isKind(.Implicit) and entry.data.isKind(.Definition)) {
                            my.found_entry = entry;
                        } else {
                            var found_ap = try my.outer.ampPath(my.outer.a, found_entry.id);
                            defer found_ap.deinit();
                            var new_ap = try my.outer.ampPath(my.outer.a, entry.id);
                            defer new_ap.deinit();
                            std.log.warn("Found ambiguous match for {f}\nnew node {} at {f}{f}sticking with old node {} at {f}{f}", .{
                                my.ap,
                                entry.id,
                                new_ap,
                                entry.data,
                                found_entry.id,
                                found_ap,
                                found_entry.data,
                            });
                        }
                    } else {
                        my.found_entry = entry;
                    }
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
                while (true) {
                    const name = entry.data.name orelse return false;
                    if (std.mem.eql(u8, part.content, name))
                        break;
                    if (ix0 == 0)
                        // We expect the tail of my.ap to match immediately. Other parts can match after dropping layers from this path to leaf.
                        return false;
                    entry = (my.outer.tree.parent(entry.id) catch return false) orelse return false;
                }
            }
            return true;
        }
    }{ .ap = ap, .outer = self };
    try self.tree.dfs(self.root.id, &cb);

    return if (cb.found_entry) |entry| entry.id else null;
}

pub fn addAncestralDependency(self: *Self, node: Tree.Id, parent: Tree.Id) !bool {
    if (node == parent)
        // No self-ancestors

        return false;

    var ancestors = &self.tree.ptr(node).ancestors;
    for (ancestors.items) |ancestor|
        if (ancestor == parent)
            return false;
    try ancestors.append(self.a, parent);
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
                _ = try my.outer.addAncestralDependency(entry.id, parent.id);
            entry.data.direct_ancestor_count = entry.data.ancestors
                .items.len;
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

            // Do not directly iterate on items since addAncestralDependency() might reallocate that
            for (0..entry.data.ancestors
                .items.len) |ix0|
            {
                const ancestor = entry.data.ancestors
                    .items[ix0];
                for (my.outer.tree.cptr(ancestor).ancestors
                    .items) |ancestor2|
                {
                    if (try my.outer.addAncestralDependency(entry.id, ancestor2))
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
        std.log.info("Found {} new ancestors, aggregating again", .{cb.new_dep_count});
    }
}

pub fn aggregateData(self: *Self) !void {
    for (self.tree.nodes.items) |*entry| {
        for (entry.data.ancestors.items) |ancestor| {
            try entry.data.aggregate(self.tree.ptr(ancestor));
        }
    }
}

pub fn updateMeta(self: *Self, node: Tree.Id, meta: Meta) !void {
    try self.tree.ptr(node).updateMeta(meta);
}

pub fn write(self: Self, parent: *rubr.naft.Node) void {
    var n = parent.node("Tree");
    defer n.deinit();

    for (self.tree.root_ids.items) |root_id| {
        try self.write_(&n, root_id);
    }
}
fn write_(self: Self, parent: *rubr.naft.Node, id: Tree.Id) !void {
    var n = parent.node("Node");
    defer n.deinit();

    n.attr("id", id);

    const node = self.tree.cptr(id).*;
    if (node.name) |name|
        n.attr("name", name);
    for (node.ancestors.items) |ancestor|
        n.attr("ancestor", ancestor);
    if (node.meta) |meta|
        meta.write(&n);
    for (node.locations.items) |location|
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

    (try tree.tree.addChild(tree.root.id)).data.init(ut.allocator, "A");
    (try tree.tree.addChild(tree.root.id)).data.init(ut.allocator, "B");
    (try tree.tree.addChild(tree.root.id)).data.init(ut.allocator, "C");

    std.debug.print("{f}", .{tree});

    try ut.expect(true);
}
