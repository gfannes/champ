const std = @import("std");

const amp = @import("amp.zig");

const rubr = @import("rubr");
const naft = rubr.naft;
const Env = rubr.Env;

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
        for (self.parts.items[0..count]) |part| {
            if (part.ap.value_at(&[_][]const u8{key})) |p| {
                if (res) |r| {
                    // For ~status, we keep the first occurence

                    if (amp.Prio.isLess(p.prio, r.prio))
                        res = p;
                    if (amp.Date.isLess(p.date, r.date))
                        res = p;
                } else {
                    res = p;
                }
            }
        }

        return res;
    }

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Chore");
        defer n.deinit();
        n.attr("id", self.node_id);
        if (self.path.len > 0)
            n.attr("path", self.path);
        n.attr("str", self.str);
        for (self.parts.items) |e|
            e.write(&n);
    }
};

// Keeps track of all def-amps and its string repr without the need for tree traversal
pub const Chores = struct {
    const Self = @This();
    const List = std.ArrayList(Chore);
    const TmpConcat = std.ArrayList([]const u8);

    env: Env,

    aral: std.heap.ArenaAllocator = undefined,
    list: List = .{},

    tmp_concat: TmpConcat = .{},

    pub fn init(self: *Self) void {
        self.aral = std.heap.ArenaAllocator.init(self.env.a);
    }
    pub fn deinit(self: *Self) void {
        self.aral.deinit();
    }

    // Returns true if tree[node_id] is an actual Chore and was thus added
    pub fn add(self: *Self, node_id: usize, tree: *const mero.Tree, defmgr: amp.DefMgr) !bool {
        const node = tree.cptr(node_id);

        if (rubr.slc.is_empty(node.org_amps.items))
            // This is not a Chore
            return false;

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

        try self.list.append(aa, chore);

        return true;
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
    var env_inst = Env.Instance{};
    env_inst.init();
    defer env_inst.deinit();

    const env = env_inst.env();

    var cl = Chores{ .env = env };
    cl.init();
    defer cl.deinit();

    var tree = mero.Tree.init(env.a);
    defer tree.deinit();

    const ch0 = try tree.addChild(null);
    ch0.data.* = mero.Node.init(env.a);

    const ch1 = try tree.addChild(null);
    ch1.data.* = mero.Node.init(env.a);

    const ch2 = try tree.addChild(null);
    ch2.data.* = mero.Node.init(env.a);

    _ = try cl.add(0, &tree);
    _ = try cl.add(1, &tree);
    _ = try cl.add(2, &tree);
}
