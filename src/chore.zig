const std = @import("std");

const amp = @import("amp.zig");

const rubr = @import("rubr");
const naft = rubr.naft;
const Log = rubr.log.Log;
const Strange = rubr.strange.Strange;

const mero = @import("mero.zig");

pub const Error = error{
    CouldNotParseAmp,
    CouldNotAppendCatchall,
    ExpectedNoCatchAll,
};

// A Tree node that contains AMP info (both def and non-defs)
// &cleanup naming conventions
pub const Chore = struct {
    const Self = @This();
    const Part = struct {
        ap: amp.Path,
        str: []const u8,
        row: usize,
        cols: rubr.index.Range,
        pub fn write(self: Part, parent: *naft.Node) void {
            var n = parent.node("Chore.Part");
            defer n.deinit();
            n.attr("str", self.str);
            n.attr("row", self.row);
            n.attr("cols.begin", self.cols.begin);
            n.attr("cols.end", self.cols.end);
        }
    };
    const Parts = std.ArrayList(Part);

    node_id: usize,
    path: []const u8 = &.{},
    // String repr of Node.org_amps + Node.agg_amps
    str: []const u8 = &.{},
    // Indicates the size of Node.org_amps in str
    org_size: usize = 0,
    parts: Parts,

    pub fn init(node_id: usize, a: std.mem.Allocator) Self {
        return Self{ .node_id = node_id, .parts = Parts.init(a) };
    }
    pub fn deinit(self: *Self) void {
        self.parts.deinit();
        self.defs.deinit();
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

pub const Def = struct {
    const Self = @This();
    pub const Ix = rubr.index.Ix(@This());

    ap: amp.Path,
    str: []const u8,
    path: []const u8,
    grove_id: usize,
    row: usize,
    cols: rubr.index.Range,

    pub fn deinit(self: *Self) void {
        self.ap.deinit();
    }

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

pub const Amp = struct {
    pub const Ix = rubr.index.Ix(@This());

    ap: amp.Path,
    def: Def.Ix,

    pub fn write(self: Amp, parent: *naft.Node) void {
        var n = parent.node("Amp");
        defer n.deinit();
        n.attr("path", self.ap);
        n.attr("def", self.def);
    }
};

// Keeps track of all AMP info and its string repr without the need for tree traversal
pub const Chores = struct {
    const Self = @This();
    const Amps = std.ArrayList(Amp);
    const List = std.ArrayList(Chore);
    const Defs = std.ArrayList(Def);
    const Catchall = struct {
        ap: amp.Path,
        str: []const u8,
        ix: Def.Ix,
    };
    const TmpConcat = std.ArrayList([]const u8);

    log: *const Log,

    aa: std.heap.ArenaAllocator,
    // All resolved (non-template) AMPs
    amps: Amps,
    list: List,
    defs: Defs,
    catchall: ?Catchall = null,

    tmp_concat: TmpConcat,

    pub fn init(log: *const Log, a: std.mem.Allocator) Self {
        return Self{
            .log = log,
            // Do not use the arena allocator here since Self will still be moved
            .aa = std.heap.ArenaAllocator.init(a),
            .amps = Amps.init(a),
            .list = List.init(a),
            .defs = Defs.init(a),
            .tmp_concat = TmpConcat.init(a),
        };
    }
    pub fn deinit(self: *Self) void {
        self.aa.deinit();
        self.amps.deinit();
        self.list.deinit();
        self.defs.deinit();
        self.tmp_concat.deinit();
    }

    pub fn setupCatchAll(self: *Self, name: []const u8) !void {
        if (self.catchall != null)
            return Error.ExpectedNoCatchAll;

        const aaa = self.aa.allocator();

        const content = try std.mem.concat(aaa, u8, &[_][]const u8{ "&:", name });

        var strange = Strange{ .content = content };
        const ap = try amp.Path.parse(&strange, aaa) orelse return Error.CouldNotParseAmp;

        const def_ix = Def.Ix.init(self.defs.items.len);
        _ = try self.appendDef(ap, &.{}, std.math.maxInt(usize), 0, .{}) orelse return Error.CouldNotAppendCatchall;

        self.catchall = Catchall{ .ap = ap, .str = content, .ix = def_ix };
    }

    // Takes deep copy of def
    // For non-templates, the def is added to the list of AMPs as well
    pub fn appendDef(self: *Self, def_ap: amp.Path, path: []const u8, grove_id: usize, row: usize, cols: rubr.index.Range) !?Amp.Ix {
        try self.log.info("appendDef() '{}'\n", .{def_ap});
        const check_fit = struct {
            needle: *const amp.Path,
            grove_id: usize,
            pub fn call(my: @This(), other: Def) bool {
                return other.ap.is_fit(my.needle.*) and my.grove_id == other.grove_id;
            }
        }{ .needle = &def_ap, .grove_id = grove_id };
        if (rubr.algo.anyOf(Def, self.defs.items, check_fit)) {
            try self.log.warning("Definition '{}' is already present in Grove {}.\n", .{ def_ap, grove_id });
            return null;
        }

        const aaa = self.aa.allocator();

        const def_ix = Def.Ix.init(self.defs.items.len);
        try self.defs.append(Def{
            .ap = try def_ap.copy(aaa),
            .str = try std.fmt.allocPrint(aaa, "{}", .{def_ap}),
            .path = path,
            .grove_id = grove_id,
            .row = row,
            .cols = cols,
        });

        if (def_ap.is_template())
            // Templates are not added to the list of resolved AMPs
            return null;

        const amp_ix = Amp.Ix.init(self.amps.items.len);
        var a = try def_ap.copy(aaa);
        a.is_definition = false;
        try self.amps.append(Amp{ .ap = a, .def = def_ix });

        return amp_ix;
    }

    pub fn resolve(self: *Self, ap: *amp.Path, grove_id: usize) !?Amp.Ix {
        // Find match in already resolved AMPs
        for (self.amps.items, 0..) |e, ix| {
            if (e.ap.is_fit(ap.*)) {
                try ap.extend(e.ap);
                return Amp.Ix.init(ix);
            }
        }

        // No direct match found: find a matching def
        const Match = struct {
            ix: Def.Ix,
            grove_id: usize,
        };
        var maybe_match: ?Match = null;

        var is_ambiguous = false;
        for (&[_]bool{ true, false }) |grove_id_must_match| {
            if (grove_id_must_match == false and maybe_match != null)
                // We found a match within the Grove of 'path': do not check for matches outside this Grove.
                continue;

            for (self.defs.items, 0..) |def, ix| {
                // We first check for a match within the Grove of 'path', in a second iteration, we check for matches outside.
                const grove_id_is_same = (def.grove_id == grove_id);
                if (grove_id_must_match != grove_id_is_same)
                    continue;

                if (def.ap.is_fit(ap.*)) {
                    if (maybe_match) |match| {
                        if (!is_ambiguous) {
                            // This is the first ambiguous match we find: report the initial match as well
                            const d = match.ix.ptr(self.defs.items);
                            try self.log.warning("Ambiguous AMP found: '{}' fits with def '{}' from '{s}'\n", .{ ap, def.ap, d.ap });
                        }
                        is_ambiguous = true;

                        try self.log.warning("Ambiguous AMP found: '{}' fits with '{}' from '{s}'\n", .{ ap, def.ap, def.ap });
                    }
                    maybe_match = Match{ .ix = Def.Ix{ .ix = ix }, .grove_id = def.grove_id };
                }
            }
        }

        if (is_ambiguous)
            return null;

        const aaa = self.aa.allocator();

        const amp_ix = Amp.Ix.init(self.amps.items.len);
        if (maybe_match) |match| {
            const def = match.ix.cptr(self.defs.items);
            if (ap.is_absolute) {
                if (ap.parts.items.len != def.ap.parts.items.len) {
                    try self.log.warning("Could not resolve '{}', it matches with '{}', but it is absolute\n", .{ ap, def.ap });
                    return null;
                }
            } else {
                try ap.extend(def.ap);
                ap.is_definition = false;
            }
            try self.amps.append(Amp{ .ap = try ap.copy(aaa), .def = match.ix });
        } else {
            if (self.catchall) |catchall| {
                try ap.prepend(catchall.ap);
                ap.is_absolute = true;
                ap.is_definition = false;

                try self.amps.append(Amp{ .ap = try ap.copy(aaa), .def = catchall.ix });
            } else {
                try self.log.warning("Could not resolve AMP '{}' and not catch-all is present\n", .{ap});
                return null;
            }
        }

        return amp_ix;
    }

    // Returns true if tree[node_id] is an actual Chore and was thus added
    pub fn add(self: *Self, node_id: usize, tree: *const mero.Tree) !bool {
        const node = tree.cptr(node_id);

        if (rubr.slice.is_empty(node.org_amps.items))
            // This is not a Chore
            return false;

        const aaa = self.aa.allocator();

        try self.tmp_concat.resize(0);
        var sep: []const u8 = "";
        var org_size: usize = 0;
        for (node.org_amps.items) |org| {
            const a = org.ix.cptr(self.amps.items);
            try self.tmp_concat.append(try std.fmt.allocPrint(aaa, "{s}{}", .{ sep, a.ap }));
            org_size += (rubr.slice.last(self.tmp_concat.items) orelse unreachable).len;
            sep = " ";
        }
        for (node.agg_amps.items) |org| {
            const a = org.ix.cptr(self.amps.items);
            try self.tmp_concat.append(try std.fmt.allocPrint(aaa, "{s}{}", .{ sep, a.ap }));
            sep = " ";
        }

        var chore = Chore.init(node_id, aaa);
        chore.str = try std.mem.concat(aaa, u8, self.tmp_concat.items);
        chore.org_size = org_size;

        var offset: usize = 0;
        for (node.org_amps.items, 0..) |org, ix| {
            var str = chore.str[offset .. offset + self.tmp_concat.items[ix].len];
            offset += str.len;
            if (ix > 0)
                // Drop the sep
                str.ptr += 1;

            const a = org.ix.cptr(self.amps.items);
            try chore.parts.append(Chore.Part{ .ap = a.ap, .str = str, .row = org.pos.row, .cols = org.pos.cols });
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
        for (self.defs.items) |e| {
            e.write(&n);
        }
        for (self.amps.items) |e| {
            e.write(&n);
        }
        for (self.list.items) |e| {
            e.write(&n);
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
