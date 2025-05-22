const std = @import("std");

const Term = @import("dto.zig").Term;
const Terms = @import("dto.zig").Terms;
const Tree = @import("dto.zig").Tree;
const Node = @import("dto.zig").Node;
const cfg = @import("../cfg.zig");
const cli = @import("../cli.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");
const chore = @import("../chore.zig");

const rubr = @import("rubr");
const Log = rubr.log.Log;
const walker = rubr.walker;
const slice = rubr.slice;
const strings = rubr.strings;
const Strange = rubr.strange.Strange;

pub const Error = error{
    ExpectedOffsets,
    ExpectedAbsoluteDef,
    OnlyOneDefAllowed,
    ExpectedAtLeastOneGrove,
    CouldNotParseAmp,
    CatchAllAmpAlreadyExists,
    ExpectedGroveId,
};

pub const Forest = struct {
    const Self = @This();

    log: *const Log,
    tree: Tree,
    chores: chore.Chores,
    a: std.mem.Allocator,

    pub fn init(log: *const Log, a: std.mem.Allocator) Self {
        return Self{
            .log = log,
            .tree = Tree.init(a),
            .chores = chore.Chores.init(log, a),
            .a = a,
        };
    }
    pub fn deinit(self: *Self) void {
        var cb = struct {
            pub fn call(_: *@This(), entry: Tree.Entry) !void {
                entry.data.deinit();
            }
        }{};
        self.tree.each(&cb) catch {};
        self.tree.deinit();
        self.chores.deinit();
    }
    pub fn reinit(self: *Self) void {
        const log = self.log;
        const a = self.a;
        self.deinit();
        self.* = Self.init(log, a);
    }

    pub fn load(self: *Self, config: *const cfg.Config, options: *const cli.Options) !void {
        var wanted_groves: [][]const u8 = options.groves.items;
        if (slice.is_empty(wanted_groves)) {
            if (config.default) |default|
                wanted_groves = default;
        }
        if (slice.is_empty(wanted_groves))
            return Error.ExpectedAtLeastOneGrove;

        for (config.groves) |cfg_grove| {
            if (strings.contains(u8, wanted_groves, cfg_grove.name))
                try self.loadGrove(&cfg_grove);
        }

        try self.collectDefs();

        try self.resolveAmps();
    }

    pub fn findFile(self: *Self, name: []const u8) ?Tree.Entry {
        for (self.tree.root_ids.items) |root_id| {
            if (self.findFile_(name, root_id)) |file|
                return file;
        }
        return null;
    }

    fn loadGrove(self: *Self, cfg_grove: *const cfg.Grove) !void {
        var cb = Cb.init(self.log, cfg_grove, &self.tree, self.a);
        defer cb.deinit();

        const dir = try std.fs.openDirAbsolute(cfg_grove.path, .{});

        var w = try walker.Walker.init(self.a);
        defer w.deinit();
        try w.walk(dir, &cb);
    }

    const Cb = struct {
        const My = @This();
        const Stack = std.ArrayList(usize);

        log: *const Log,
        cfg_grove: *const cfg.Grove,
        tree: *Tree,
        node_stack: Stack,
        file_count: usize = 0,

        pub fn init(log: *const Log, cfg_grove: *const cfg.Grove, tree: *Tree, a: std.mem.Allocator) Cb {
            return Cb{
                .log = log,
                .cfg_grove = cfg_grove,
                .tree = tree,
                .node_stack = Stack.init(a),
            };
        }
        pub fn deinit(my: *My) void {
            my.node_stack.deinit();
        }

        pub fn call(my: *Cb, dir: std.fs.Dir, path: []const u8, maybe_offsets: ?walker.Offsets, kind: walker.Kind) !void {
            switch (kind) {
                walker.Kind.Enter => {
                    var name: []const u8 = undefined;
                    var node_type: Node.Type = undefined;
                    if (maybe_offsets) |offsets| {
                        name = path[offsets.name..];
                        node_type = Node.Type.Folder;
                    } else {
                        name = "<ROOT>";
                        node_type = Node.Type.Grove;
                    }

                    const entry = try my.tree.addChild(slice.last(my.node_stack.items));
                    const n = entry.data;
                    n.* = Node.init(my.tree.a);
                    n.type = node_type;
                    n.path = try n.a.dupe(u8, path);

                    try my.node_stack.append(entry.id);
                },
                walker.Kind.Leave => {
                    _ = my.node_stack.pop();
                },
                walker.Kind.File => {
                    const offsets = maybe_offsets orelse return Error.ExpectedOffsets;
                    const name = path[offsets.name..];

                    if (my.cfg_grove.include) |include| {
                        const ext = std.fs.path.extension(name);
                        if (!strings.contains(u8, include, ext))
                            // Skip this extension
                            return;
                    }

                    const my_ext = std.fs.path.extension(name);
                    if (mero.Language.from_extension(my_ext)) |language| {
                        if (my.cfg_grove.max_count) |max_count|
                            if (my.file_count >= max_count)
                                return;
                        my.file_count += 1;

                        const file = try dir.openFile(name, .{});
                        defer file.close();

                        const stat = try file.stat();
                        const size_is_ok = if (my.cfg_grove.max_size) |max_size| stat.size < max_size else true;
                        if (!size_is_ok)
                            return;

                        const entry = try my.tree.addChild(slice.last(my.node_stack.items));
                        const n = entry.data;
                        n.* = Node.init(my.tree.a);
                        n.type = Node.Type.File;
                        n.path = try n.a.dupe(u8, path);
                        n.language = language;
                        n.content = try file.readToEndAlloc(n.a, std.math.maxInt(usize));
                        n.grove_id = my.cfg_grove.id;

                        var parser = try mero.Parser.init(entry.id, my.tree, my.tree.a);
                        defer parser.deinit();

                        try parser.parse();
                    } else {
                        try my.log.warning("Unsupported extension '{s}' for '{}' '{s}'\n", .{ my_ext, dir, path });
                    }
                },
            }
        }
    };

    fn resolveAmps(self: *Self) !void {
        try self.chores.setupCatchAll("?");

        var cb = struct {
            const My = @This();

            tree: *const Tree,
            chores: *chore.Chores,
            log: *const Log,
            a: std.mem.Allocator,

            terms: *const Terms = undefined,
            path: []const u8 = &.{},
            grove_id: ?usize = null,

            pub fn call(my: *My, entry: Tree.Entry) !void {
                const n = entry.data;
                switch (n.type) {
                    Node.Type.Grove => {},
                    Node.Type.Folder => {
                        my.path = n.path;
                    },
                    Node.Type.File => {
                        my.path = n.path;
                        my.terms = &n.terms;
                        if (n.grove_id == null)
                            return Error.ExpectedGroveId;
                        my.grove_id = n.grove_id;
                    },
                    else => {
                        var line: usize = n.content_rows.begin;
                        var cols: rubr.index.Range = .{};
                        for (n.line.terms_ixr.begin..n.line.terms_ixr.end) |term_ix| {
                            const term = &my.terms.items[term_ix];

                            cols.begin = cols.end;
                            cols.end += term.word.len;

                            if (term.kind == Term.Kind.Amp or term.kind == Term.Kind.Checkbox) {
                                var strange = Strange{ .content = term.word };
                                var path = try amp.Path.parse(&strange, my.a) orelse return Error.CouldNotParseAmp;
                                defer path.deinit();
                                if (!path.is_definition) {
                                    const grove_id = my.grove_id orelse return Error.ExpectedGroveId;
                                    if (try my.chores.resolve(&path, grove_id)) |ix| {
                                        try n.orgs.append(mero.Node.Org{ .ix = ix, .pos = mero.Node.Pos{ .row = line, .cols = cols } });
                                    } else {
                                        try my.log.warning("Could not resolve amp '{}' in '{s}'\n", .{ path, my.path });
                                    }
                                }
                            } else if (term.kind == Term.Kind.Newline) {
                                line += term.word.len;
                                cols = .{};
                            }
                        }

                        _ = try my.chores.add(entry.id, my.tree);
                    },
                }
            }
        }{
            .tree = &self.tree,
            .chores = &self.chores,
            .log = self.log,
            .a = self.a,
        };
        try self.tree.dfsAll(true, &cb);
    }

    fn collectDefs(self: *Self) !void {
        // Expects Node.orgs to still be empty
        var cb = struct {
            const My = @This();

            tree: *Tree,
            chores: *chore.Chores,
            log: *const Log,
            a: std.mem.Allocator,

            terms: ?*const Terms = null,
            path: []const u8 = &.{},
            is_new_file: bool = false,
            grove_id: ?usize = null,

            pub fn call(my: *My, entry: Tree.Entry) !void {
                const n = entry.data;
                std.debug.assert(n.orgs.items.len == 0);

                switch (n.type) {
                    Node.Type.Grove => {},
                    Node.Type.Folder => {
                        my.path = n.path;
                    },
                    Node.Type.File => {
                        my.path = n.path;
                        my.terms = &n.terms;
                        my.is_new_file = true;
                        if (n.grove_id == null)
                            return Error.ExpectedGroveId;
                        my.grove_id = n.grove_id;
                    },
                    else => {
                        defer my.is_new_file = false;

                        // Search n.line for a def AMP
                        var line: usize = n.content_rows.begin;
                        var cols: rubr.index.Range = .{};

                        for (n.line.terms_ixr.begin..n.line.terms_ixr.end) |term_ix| {
                            const terms = my.terms orelse unreachable;
                            const term = &terms.items[term_ix];

                            cols.begin = cols.end;
                            cols.end += term.word.len;

                            if (term.kind == Term.Kind.Amp) {
                                var strange = Strange{ .content = term.word };

                                var def_ap = try amp.Path.parse(&strange, my.a) orelse return Error.CouldNotParseAmp;
                                defer def_ap.deinit();
                                if (def_ap.is_definition) {
                                    if (n.def != null)
                                        return Error.OnlyOneDefAllowed;
                                    // Make the def amp absolute, if necessary
                                    if (!def_ap.is_absolute) {
                                        var child_id = entry.id;
                                        const maybe_parent_def: ?amp.Path = block: while (true) {
                                            if (try my.tree.parent(child_id)) |parent| {
                                                if (parent.data.def) |d| {
                                                    const pdef = d.ix.cptr(my.chores.amps.items);
                                                    break :block pdef.ap;
                                                } else {
                                                    child_id = parent.id;
                                                }
                                            } else {
                                                break :block null;
                                            }
                                        };
                                        if (maybe_parent_def) |parent_def| {
                                            try def_ap.prepend(parent_def);
                                            def_ap.is_definition = true;
                                        } else {
                                            try my.log.warning("Could not find parent def for non-absolute '{}', making it absolute as it is\n", .{def_ap});
                                            def_ap.is_absolute = true;
                                        }
                                    }

                                    // Collect all defs in a separate struct
                                    const grove_id = my.grove_id orelse return Error.ExpectedGroveId;
                                    const pos = mero.Node.Pos{ .row = line, .cols = cols };
                                    if (try my.chores.appendDef(def_ap, my.path, grove_id, pos.row, pos.cols)) |ix| {
                                        n.def = mero.Node.Amp{ .ix = ix, .pos = pos };
                                    } else {
                                        try my.log.warning("Duplicate definition found in '{s}'\n", .{my.path});
                                    }
                                }
                            } else if (term.kind == Term.Kind.Newline) {
                                line += term.word.len;
                                cols = .{};
                            }
                        }

                        if (my.is_new_file) {
                            switch (n.type) {
                                Node.Type.Paragraph => {
                                    // A def on the first line is copied to the File as well
                                    if (try my.tree.parent(entry.id)) |parent|
                                        parent.data.def = n.def;
                                },
                                else => {},
                            }
                        }
                    },
                }
            }
        }{ .tree = &self.tree, .chores = &self.chores, .log = self.log, .a = self.a };
        try self.tree.dfsAll(true, &cb);
    }

    fn findFile_(self: *Self, name: []const u8, id: Tree.Id) ?Tree.Entry {
        const n = self.tree.ptr(id);
        switch (n.type) {
            mero.Node.Type.File => {
                if (std.mem.endsWith(u8, n.path, name))
                    return Tree.Entry{ .id = id, .data = n };
            },
            mero.Node.Type.Folder, mero.Node.Type.Grove => {
                for (self.tree.childIds(id)) |child_id| {
                    if (self.findFile_(name, child_id)) |file|
                        return file;
                }
            },
            else => {},
        }
        return null;
    }
};
