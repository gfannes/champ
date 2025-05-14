const std = @import("std");

const amp = @import("amp.zig");

const rubr = @import("rubr");
const naft = rubr.naft;
const Log = rubr.log.Log;
const Strange = rubr.strange.Strange;

const mero = @import("mero.zig");

pub const Error = error{
    CouldNotParseAmp,
};

// A Tree node that contains AMP info (both def and non-defs)
// &cleanup naming conventions
pub const Chore = struct {
    const Self = @This();
    const Amp = struct {
        path: amp.Path,
        str: []const u8,
        row: usize,
        cols: rubr.index.Range,
        pub fn write(self: Amp, parent: *naft.Node) void {
            var n = parent.node("Amp");
            defer n.deinit();
            n.attr("str", self.str);
            n.attr("row", self.row);
            n.attr("cols.begin", self.cols.begin);
            n.attr("cols.end", self.cols.end);
        }
    };
    const Amps = std.ArrayList(Amp);

    node_id: usize,
    path: []const u8 = &.{},
    str: []const u8 = &.{},
    amps: Amps,

    pub fn init(node_id: usize, a: std.mem.Allocator) Self {
        return Self{ .node_id = node_id, .amps = Amps.init(a) };
    }
    pub fn deinit(self: *Self) void {
        self.amps.deinit();
        self.defs.deinit();
    }

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Chore");
        defer n.deinit();
        n.attr("id", self.node_id);
        if (self.path.len > 0)
            n.attr("path", self.path);
        for (self.amps.items) |e|
            e.write(&n);
    }
};

pub const Def = struct {
    amp: amp.Path,
    str: []const u8,
    path: []const u8,
    row: usize,
    cols: rubr.index.Range,
    pub fn write(self: Def, parent: *naft.Node) void {
        var n = parent.node("Def");
        defer n.deinit();
        n.attr("str", self.str);
        n.attr("path", self.path);
        n.attr("row", self.row);
        n.attr("cols.begin", self.cols.begin);
        n.attr("cols.end", self.cols.end);
    }
};

// Keeps track of all AMP info and its string repr without the need for tree traversal
pub const Chores = struct {
    const Self = @This();
    const List = std.ArrayList(Chore);
    const Defs = std.ArrayList(Def);
    const TmpConcat = std.ArrayList([]const u8);

    log: *const Log,

    aa: std.heap.ArenaAllocator,
    list: List,
    defs: Defs,
    def_catchall_amp: ?amp.Path = null,
    def_catchall_str: []const u8 = &.{},
    tmp_concat: TmpConcat,

    pub fn init(log: *const Log, a: std.mem.Allocator) Self {
        return Self{
            .log = log,
            // Do not use the arena allocator here since Self will still be moved
            .aa = std.heap.ArenaAllocator.init(a),
            .list = List.init(a),
            .defs = Defs.init(a),
            .tmp_concat = TmpConcat.init(a),
        };
    }
    pub fn deinit(self: *Self) void {
        self.aa.deinit();
        self.list.deinit();
        self.defs.deinit();
        self.tmp_concat.deinit();
    }

    pub fn setupCatchAll(self: *Self, name: []const u8) !void {
        if (self.def_catchall_amp) |*e|
            e.deinit();

        const aaa = self.aa.allocator();

        const content = try std.mem.concat(aaa, u8, &[_][]const u8{ "&!:", name });

        var strange = Strange{ .content = content };
        self.def_catchall_amp = try amp.Path.parse(&strange, aaa);

        if (self.def_catchall_amp == null)
            return Error.CouldNotParseAmp;
        self.def_catchall_str = content;
    }

    // Keeps a shallow copy of 'def'
    pub fn appendDef(self: *Self, def: amp.Path, path: []const u8, row: usize, cols: rubr.index.Range) !bool {
        const check_fit = struct {
            needle: *const amp.Path,
            pub fn call(my: @This(), other: Def) bool {
                return other.amp.is_fit(my.needle.*);
            }
        }{ .needle = &def };
        if (rubr.algo.anyOf(Def, self.defs.items, check_fit)) {
            try self.log.warning("Definition '{}' is already present.\n", .{def});
            return false;
        }

        // Shallow copy
        const aaa = self.aa.allocator();
        try self.defs.append(Def{
            .amp = def,
            .str = try std.fmt.allocPrint(aaa, "{}", .{def}),
            .path = path,
            .row = row,
            .cols = cols,
        });
        return true;
    }

    pub fn resolve(self: Self, path: *amp.Path) !bool {
        var maybe_fit_ix: ?usize = null;
        var is_ambiguous = false;
        for (self.defs.items, 0..) |def, ix| {
            if (def.amp.is_fit(path.*)) {
                if (maybe_fit_ix) |fit_ix| {
                    if (!is_ambiguous)
                        try self.log.warning("Ambiguous AMP found: '{}' fits with '{}'\n", .{ path, self.defs.items[fit_ix] });
                    is_ambiguous = true;

                    try self.log.warning("Ambiguous AMP found: '{}' fits with '{}'\n", .{ path, def.amp });
                }
                maybe_fit_ix = ix;
            }
        }

        if (is_ambiguous)
            return false;

        if (maybe_fit_ix) |fit_ix| {
            const def = self.defs.items[fit_ix];
            if (path.is_absolute) {
                if (path.parts.items.len != def.amp.parts.items.len) {
                    try self.log.warning("Could not resolve '{}', it matches with '{}', but it is absolute\n", .{ path, def.amp });
                    return false;
                }
                return true;
            } else {
                const count_to_add = def.amp.parts.items.len - path.parts.items.len;
                const new_parts = try path.parts.addManyAt(0, count_to_add);
                std.mem.copyForwards(amp.Part, new_parts, def.amp.parts.items[0..count_to_add]);
                path.is_absolute = true;
                return true;
            }
        } else {
            if (self.def_catchall_amp) |ca_def| {
                const new_parts = try path.parts.addManyAt(0, ca_def.parts.items.len);
                std.mem.copyForwards(amp.Part, new_parts, ca_def.parts.items);
                path.is_absolute = true;
                return true;
            } else {
                try self.log.warning("Could not resolve AMP '{}' and not catch-all is present\n", .{path});
                return false;
            }
        }
    }

    // Return true if tree[node_id] is an actual Chore and was thus added
    pub fn add(self: *Self, node_id: usize, tree: *const mero.Tree) !bool {
        const node = tree.cptr(node_id);

        const aaa = self.aa.allocator();

        try self.tmp_concat.resize(0);
        var sep: []const u8 = "";
        for (node.orgs.items) |org| {
            try self.tmp_concat.append(try std.fmt.allocPrint(aaa, "{s}{}", .{ sep, org.amp }));
            sep = " ";
        }

        if (self.tmp_concat.items.len == 0)
            // This is not a Chore
            return false;

        var chore = Chore.init(node_id, aaa);
        chore.str = try std.mem.concat(aaa, u8, self.tmp_concat.items);

        var offset: usize = 0;
        for (node.orgs.items, 0..) |org, ix| {
            var str = chore.str[offset .. offset + self.tmp_concat.items[ix].len];
            offset += str.len;
            if (ix > 0)
                // Drop the sep
                str.ptr += 1;

            try chore.amps.append(Chore.Amp{ .path = org.amp, .str = str, .row = org.pos.row, .cols = org.pos.cols });
        }

        // Lookup path
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
        var n = parent.node("Chores");
        defer n.deinit();
        for (self.defs.items) |def| {
            def.write(&n);
        }
        for (self.list.items) |chore| {
            chore.write(&n);
        }
    }
};

test "chore" {
    const ut = std.testing;

    var log = Log{};
    log.init();
    defer log.deinit();

    var cl = Chores.init(&log, ut.allocator);
    defer cl.deinit();

    var tree = mero.Tree.init(ut.allocator);
    defer tree.deinit();

    const ch0 = try tree.addChild(null);
    ch0.data.* = mero.Node.init(ut.allocator);

    const ch1 = try tree.addChild(null);
    ch1.data.* = mero.Node.init(ut.allocator);

    const ch2 = try tree.addChild(null);
    ch2.data.* = mero.Node.init(ut.allocator);

    _ = try cl.add(0, &tree);
    _ = try cl.add(1, &tree);
    _ = try cl.add(2, &tree);
}
