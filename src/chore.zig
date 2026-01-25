const std = @import("std");

const amp = @import("amp.zig");

const rubr = @import("rubr");
const naft = rubr.naft;

const mero = @import("mero.zig");
const filex = @import("filex.zig");

// A Tree node that contains AMP info (both def and non-defs)
// &cleanup naming conventions
pub const Chore = struct {
    const Self = @This();
    const Part = struct {
        ap: amp.Path,
        str: []const u8,
        pos: filex.Pos,
        pub fn write(self: Part, parent: *naft.Node) void {
            var n = parent.node("Chore.Part");
            defer n.deinit();
            n.attr("str", self.str);
            n.attr("row", self.pos.row);
            n.attr("cols.begin", self.pos.cols.begin);
            n.attr("cols.end", self.pos.cols.end);
        }
    };
    const Parts = std.ArrayList(Part);

    a: std.mem.Allocator,
    node_id: usize, // Id for forest.tree
    path: []const u8 = &.{},
    // String repr of Node.org_amps + Node.agg_amps
    str: []const u8 = &.{},

    parts: Parts = .{},
    // Indicates the number of Parts that are orgs
    org_count: usize = 0,

    pub fn init(node_id: usize, a: std.mem.Allocator) Self {
        return Self{ .node_id = node_id, .a = a };
    }
    pub fn deinit(self: *Self) void {
        self.parts.deinit();
    }

    pub fn isDone(self: Self) bool {
        var strange = rubr.strng.Strange{ .content = "&status:done" };
        var done_ap = (amp.Path.parse(&strange, self.a) catch null) orelse unreachable;
        defer done_ap.deinit();
        for (self.parts.items) |part| {
            if (part.ap.isFit(done_ap))
                return true;
        }
        return false;
    }

    pub const Where = enum { Org, Any };
    pub fn value(self: Self, key: []const u8, where: Where) ?*const amp.Path.Part {
        var res: ?*const amp.Path.Part = null;

        const count = switch (where) {
            .Org => self.org_count,
            .Any => self.parts.items.len,
        };

        var res_where: Where = .Org;
        for (self.parts.items[0..count], 0..) |part, ix0| {
            if (part.ap.value_at(&[_][]const u8{key})) |p| {
                const current_where: Where = if (ix0 < self.org_count) .Org else .Any;

                if (res) |r| {
                    switch (current_where) {
                        .Org => {
                            res = p;
                            res_where = current_where;
                        },
                        .Any => {
                            if (res_where == current_where) {
                                // For ~status, we keep the first occurence

                                if (amp.Prio.order(p.prio, r.prio) == .lt) {
                                    res = p;
                                    res_where = current_where;
                                }
                                if (amp.Date.order(p.date, r.date) == .lt) {
                                    res = p;
                                    res_where = current_where;
                                }
                            }
                        },
                    }
                } else {
                    res = p;
                    res_where = current_where;
                }
            }
        }

        return res;
    }

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Chore");
        defer n.deinit();
        n.attr("node_id", self.node_id);
        if (self.path.len > 0)
            n.attr("path", self.path);
        n.attr("str", self.str);
        for (self.parts.items) |e|
            e.write(&n);
    }

    pub fn format(self: Self, w: *std.Io.Writer) !void {
        var root = naft.Node{ .w = w };
        defer root.deinit();
        self.write(&root);
    }
};

// Keeps track of all def-amps and its string repr without the need for tree traversal
pub const Chores = struct {
    const Self = @This();
    const List = std.ArrayList(Chore);
    const TmpConcat = std.ArrayList([]const u8);

    env: rubr.Env,
    aral: std.heap.ArenaAllocator,

    list: List = .{},

    tmp_concat: TmpConcat = .{},

    pub fn init(env: rubr.Env) Self {
        return .{
            .env = env,
            .aral = std.heap.ArenaAllocator.init(env.a),
        };
    }
    pub fn deinit(self: *Self) void {
        self.aral.deinit();
    }

    // Returns true if tree[node_id] is an actual Chore and was thus added
    // defmgr is needed to lookup the amp.Path
    pub fn add(self: *Self, node_id: usize, tree: *const mero.Tree, defmgr: amp.DefMgr) !?usize {
        const node = tree.cptr(node_id);

        if (rubr.slc.isEmpty(node.org_amps.items))
            // This is not a Chore
            return null;
        if (node.type == .File)
            // Skip Files
            return null;

        const aa = self.aral.allocator();

        try self.tmp_concat.resize(aa, 0);
        var sep: []const u8 = "";
        var org_count: usize = 0;
        for (node.org_amps.items) |org| {
            const a = org.ix.cptr(defmgr.defs.items);
            try self.tmp_concat.append(aa, try std.fmt.allocPrint(aa, "{s}{f}", .{ sep, a.ap }));
            org_count += 1;
            sep = " ";
        }
        for (node.agg_amps.items) |agg| {
            const a = agg.cptr(defmgr.defs.items);
            try self.tmp_concat.append(aa, try std.fmt.allocPrint(aa, "{s}{f}", .{ sep, a.ap }));
            sep = " ";
        }

        var chore = Chore.init(node_id, aa);
        chore.str = try std.mem.concat(aa, u8, self.tmp_concat.items);
        chore.org_count = org_count;

        var offset: usize = 0;
        var ix: usize = 0;

        for (node.org_amps.items) |org| {
            defer ix += 1;

            var str = chore.str[offset .. offset + self.tmp_concat.items[ix].len];
            offset += str.len;
            if (ix > 0)
                // Drop the sep
                str.ptr += 1;

            const a = org.ix.cptr(defmgr.defs.items);
            try chore.parts.append(aa, Chore.Part{ .ap = a.ap, .str = str, .pos = org.pos });
        }

        for (node.agg_amps.items) |agg| {
            defer ix += 1;

            var str = chore.str[offset .. offset + self.tmp_concat.items[ix].len];
            offset += str.len;
            if (ix > 0)
                // Drop the sep
                str.ptr += 1;

            const a = agg.cptr(defmgr.defs.items);
            try chore.parts.append(aa, Chore.Part{ .ap = a.ap, .str = str, .pos = .{} });
        }

        // Lookup path
        var maybe_id = rubr.opt.value(node_id);
        while (maybe_id) |id| {
            const n = tree.cptr(id);
            switch (n.type) {
                mero.Node.Type.Grove, mero.Node.Type.Folder, mero.Node.Type.File => chore.path = n.path,
                else => {},
            }
            maybe_id = if (try tree.parent(id)) |p| p.id else null;
            if (chore.path.len > 0)
                // We found a path: stop search
                maybe_id = null;
        }

        const chore_ix = self.list.items.len;
        try self.list.append(aa, chore);

        return chore_ix;
    }

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Chores");
        defer n.deinit();
        for (self.list.items) |e| {
            e.write(&n);
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

    _ = try chores.add(0, &tree, defmgr);
    _ = try chores.add(1, &tree, defmgr);
    _ = try chores.add(2, &tree, defmgr);
}
