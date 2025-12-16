const std = @import("std");
const Def = @import("Def.zig");
const Path = @import("Path.zig");
const filex = @import("../filex.zig");
const rubr = @import("rubr");

const Self = @This();

const Defs = std.ArrayList(Def);
const TmpConcat = std.ArrayList([]const u8);

env: rubr.Env,
phony_prefix: []const u8,

aral: std.heap.ArenaAllocator = undefined,
defs: Defs = .{},

tmp_concat: TmpConcat = .{},

pub fn init(self: *Self) void {
    self.aral = std.heap.ArenaAllocator.init(self.env.a);
}
pub fn deinit(self: *Self) void {
    self.aral.deinit();
}

// Takes deep copy of def
pub fn appendDef(self: *Self, def_ap: Path, grove_id: usize, path: []const u8, node_id: usize, pos: filex.Pos) !?Def.Ix {
    if (self.env.log.level(1)) |w| {
        try w.print("appendDef() '{f}'\n", .{def_ap});
    }

    const check_fit = struct {
        needle: *const Path,
        grove_id: usize,
        pub fn call(my: @This(), other: Def) bool {
            const other_grove_id = (other.location orelse return false).grove_id;
            return other.ap.isFit(my.needle.*) and my.grove_id == other_grove_id;
        }
    }{ .needle = &def_ap, .grove_id = grove_id };
    if (rubr.algo.anyOf(Def, self.defs.items, check_fit)) {
        try self.env.log.warning("Definition '{f}' is already present in Grove {}.\n", .{ def_ap, grove_id });
        return null;
    }

    const aa = self.aral.allocator();

    const def_ix = Def.Ix.init(self.defs.items.len);
    try self.defs.append(aa, .{
        .ap = try def_ap.copy(aa),
        .location = .{
            .grove_id = grove_id,
            .path = path,
            .node_id = node_id,
            .pos = pos,
        },
    });

    return def_ix;
}

pub fn resolve(self: *Self, ap: *Path, grove_id: usize) !?Def.Ix {
    // std.debug.print("Resolving {f}\n", .{ap});

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

            if (def.ap.isFit(ap.*)) {
                if (maybe_match) |match| {
                    if (!is_ambiguous) {
                        // This is the first ambiguous match we find: report the initial match as well
                        const d = match.ix.ptr(self.defs.items);
                        try self.env.log.warning("Ambiguous AMP found: '{f}' fits with def '{f}' and '{f}'\n", .{ ap, def.ap, d.ap });
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
        if (ap.is_absolute) {
            if (ap.parts.items.len != def.ap.parts.items.len) {
                try self.env.log.warning("Could not resolve '{f}', it matches with '{f}', but it is absolute\n", .{ ap, def.ap });
                return null;
            }
        } else {
            try ap.extend(def.ap);
            ap.is_definition = false;
        }

        if (def.ap.is_template()) {
            // std.debug.print("{f} matches with template {f}\n", .{ ap, def.ap });
            try def.ap.evaluate(ap);

            for (self.defs.items, 0..) |d, ix0| {
                if ((d.template orelse continue).eql(match.ix)) {
                    if (d.ap.isFit(ap.*))
                        // We found a def that refers to the same template and with the same path: we return this iso adding a new phony def
                        return Def.Ix.init(ix0);
                }
            }

            // Add a phony def for this new template instantiation
            const def_ix = Def.Ix.init(self.defs.items.len);
            try self.defs.append(aa, .{ .ap = try ap.copy(aa), .template = match.ix });
            return def_ix;
        } else {
            return match.ix;
        }
    } else {
        // No match found, add a phony def
        try ap.prependString(self.phony_prefix);
        ap.is_absolute = true;
        ap.is_definition = false;

        const def_ix = Def.Ix.init(self.defs.items.len);
        try self.defs.append(aa, .{ .ap = try ap.copy(aa) });

        return def_ix;
    }
}

pub fn write(self: Self, parent: *rubr.naft.Node) void {
    var n = parent.node("Chores");
    defer n.deinit();
    for (self.defs.items) |e| {
        e.write(&n);
    }
}

pub fn get(self: Self, ix: Def.Ix) ?*const Def {
    return ix.cget(self.defs.items);
}
