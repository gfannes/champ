const std = @import("std");
const Def = @import("Def.zig");
const Path = @import("Path.zig");
const filex = @import("../filex.zig");
const rubr = @import("../rubr.zig");

const Self = @This();

const Defs = std.ArrayList(Def);
const TmpConcat = std.ArrayList([]const u8);

env: rubr.Env,
// &todo: use a normal allocator
aral: std.heap.ArenaAllocator,
// &todo: is this still necessary? remove if possible
phony_prefix: []const u8,

defs: Defs = .empty,

tmp_concat: TmpConcat = .empty,

pub fn init(env: rubr.Env, phony_prefix: []const u8) Self {
    return .{
        .env = env,
        .aral = std.heap.ArenaAllocator.init(env.a),
        .phony_prefix = phony_prefix,
    };
}
pub fn deinit(self: *Self) void {
    self.aral.deinit();
}

// Takes deep copy of def
pub fn appendDef(self: *Self, def_ap: Path, grove_id: usize, filepath: []const u8, node_id: usize, pos: filex.Pos) !?Def.Ix {
    if (self.env.log.level(1)) |w| {
        try w.print("appendDef() '{f}'\n", .{def_ap});
    }

    const check_fit = struct {
        needle: *const Path,
        grove_id: usize,
        pub fn call(my: @This(), other: Def) bool {
            const other_grove_id = (other.location orelse return false).grove_id;
            return other.path.isFit(my.needle.*) and my.grove_id == other_grove_id;
        }
    }{ .needle = &def_ap, .grove_id = grove_id };
    if (rubr.algo.indexOfFirst(Def, self.defs.items, check_fit)) |ix| {
        try self.env.log.warning("Definition '{f}' from '{s}' is already present in Grove {}: {f}.\n", .{ def_ap, filepath, grove_id, self.defs.items[ix] });
        return null;
    }

    const aa = self.aral.allocator();

    const def_ix = Def.Ix.init(self.defs.items.len);
    try self.defs.append(aa, .{
        .path = try def_ap.copy(aa),
        .meta = .{ .a = aa },
        .location = .{
            .grove_id = grove_id,
            .filepath = filepath,
            .node_id = node_id,
            .pos = pos,
        },
    });

    return def_ix;
}

pub fn appendUnnamedDef(self: *Self, grove_id: usize, filepath: []const u8, node_id: usize, pos: filex.Pos) !Def.Ix {
    const aa = self.aral.allocator();

    const def_ix = Def.Ix.init(self.defs.items.len);
    var path = Path.init(aa);
    try path.parts.append(aa, Path.Part{ .content = "_unnamed" });
    try path.parts.append(aa, Path.Part{ .content = try std.fmt.allocPrint(aa, "{}", .{self.defs.items.len}) });

    try self.defs.append(aa, .{
        .path = path,
        .meta = .{ .a = aa },
        .location = .{
            .grove_id = grove_id,
            .filepath = filepath,
            .node_id = node_id,
            .pos = pos,
        },
    });

    return def_ix;
}

pub fn resolve(self: *Self, path: *Path, grove_id: usize) !?Def.Ix {
    // std.debug.print("Resolving {f}\n", .{path});

    // Find matching def
    const Match = struct {
        ix: Def.Ix,
        grove_id: usize,
    };
    var maybe_match: ?Match = null;

    // Search defs, first for matching grove_id, second for all groves
    var is_ambiguous = false;
    for (&[_]bool{ true, false }) |grove_id_must_match| {
        if (grove_id_must_match == false and maybe_match != null)
            // We found a match within the Grove of 'path': do not check for matches outside this Grove.
            continue;

        for (self.defs.items, 0..) |def, ix| {
            const def_grove_id = (def.location orelse continue).grove_id;
            // We first check for a match within the Grove of 'path', in a second iteration, we check for matches outside.
            const grove_id_is_same = (def_grove_id == grove_id);
            if (grove_id_must_match != grove_id_is_same)
                continue;

            if (def.path.isFit(path.*)) {
                if (maybe_match) |match| {
                    if (!is_ambiguous) {
                        // This is the first ambiguous match we find: report the initial match as well
                        const d = match.ix.ptr(self.defs.items);
                        try self.env.log.warning("Ambiguous AMP found: '{f}' fits with def '{f}' and '{f}'\n", .{ path, def, d });
                    }
                    is_ambiguous = true;
                }
                maybe_match = Match{ .ix = .{ .ix = ix }, .grove_id = def_grove_id };
            }
        }
    }

    if (is_ambiguous)
        return null;

    const aa = self.aral.allocator();

    if (maybe_match) |match| {
        const def = match.ix.cptr(self.defs.items);
        if (path.is_absolute) {
            if (path.parts.items.len != def.path.parts.items.len) {
                try self.env.log.warning("Could not resolve '{f}', it matches with '{f}', but it is absolute\n", .{ path, def.path });
                return null;
            }
        } else {
            try path.extend(def.path);
            path.is_definition = false;
        }

        return match.ix;
    } else {
        // No match found, add a phony def
        try path.prependString(self.phony_prefix);
        path.is_absolute = true;
        path.is_definition = false;

        const def_ix = Def.Ix.init(self.defs.items.len);
        try self.defs.append(aa, .{ .path = try path.copy(aa), .meta = .{ .a = aa } });

        return def_ix;
    }
}

pub fn write(self: Self, parent: *rubr.naft.Node) void {
    var n = parent.node("Chores");
    defer n.deinit();
    for (self.defs.items, 0..) |e, ix0| {
        e.write(&n, ix0);
    }
}

pub fn get(self: Self, ix: Def.Ix) ?*const Def {
    return ix.cget(self.defs.items);
}
