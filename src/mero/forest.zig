const std = @import("std");

const Term = @import("dto.zig").Term;
const Terms = @import("dto.zig").Terms;
const Tree = @import("dto.zig").Tree;
const Node = @import("dto.zig").Node;
const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");
const chore = @import("../chore.zig");
const filex = @import("../filex.zig");
const Chores = @import("../chore.zig").Chores;

const rubr = @import("rubr");
const Env = rubr.Env;
const walker = rubr.walker;
const strings = rubr.strings;

pub const Error = error{
    ExpectedOffsets,
    OnlyOneDefAllowed,
    ExpectedAtLeastOneGrove,
    CouldNotParseAmp,
    ExpectedGroveId,
    TooManyIterations,
};

pub const Forest = struct {
    const Self = @This();

    env: Env,
    aral: std.heap.ArenaAllocator = undefined,
    valid: bool = false,
    tree: Tree = undefined,
    defmgr: amp.DefMgr = undefined,
    chores: Chores = undefined,

    pub fn init(self: *Self) void {
        // &perf: Using a FBA works a bit faster.
        // if (builtin.mode == .ReleaseFast) {
        //     if (self.config.max_memsize) |max_memsize| {
        //         try self.stdoutw.print("Running with max_memsize {}MB\n", .{max_memsize / 1024 / 1024});
        //         self.maybe_fba = FBA.init(try self.gpaa.alloc(u8, max_memsize));
        //         // Rewire self.a to this fba
        //         self.a = (self.maybe_fba orelse unreachable).allocator();
        //     }
        // }
        self.aral = std.heap.ArenaAllocator.init(self.env.a);
        self.tree = Tree.init(self.env.a);
        self.defmgr = .{ .env = self.env, .phony_prefix = "?" };
        self.defmgr.init();
        self.chores = .{ .env = self.env };
        self.chores.init();
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
        self.defmgr.deinit();
        self.aral.deinit();
    }
    pub fn reinit(self: *Self) void {
        const env = self.env;

        self.deinit();

        self.* = Self{ .env = env };
        self.init();
    }

    pub fn load(self: *Self, config: *const cfg.file.Config, cli_args: *const cfg.cli.Args) !void {
        var wanted_groves: [][]const u8 = cli_args.groves.items;
        if (rubr.slc.is_empty(wanted_groves)) {
            if (config.default) |default|
                wanted_groves = default;
        }
        if (rubr.slc.is_empty(wanted_groves))
            return error.ExpectedAtLeastOneGrove;

        for (config.groves) |cfg_grove| {
            if (strings.contains(u8, wanted_groves, cfg_grove.name))
                try self.loadGrove(&cfg_grove);
        }

        // &todo: Measure/print performance

        try self.collectDefs();

        try self.resolveAmps();

        try self.aggregateAmps();

        try self.createChores();

        self.valid = true;
    }

    pub fn findFile(self: *Self, name: []const u8) ?Tree.Entry {
        for (self.tree.root_ids.items) |root_id| {
            if (self.findFile_(name, root_id)) |file|
                return file;
        }
        return null;
    }

    fn loadGrove(self: *Self, cfg_grove: *const cfg.file.Grove) !void {
        var cb = Cb.init(self.env, self.aral.allocator(), cfg_grove, &self.tree);
        defer cb.deinit();

        var dir = try std.fs.openDirAbsolute(cfg_grove.path, .{});
        defer dir.close();

        var w = walker.Walker{ .env = self.env };
        defer w.deinit();
        try w.walk(dir, &cb);
    }

    const Cb = struct {
        const My = @This();
        const Stack = std.ArrayList(usize);

        env: Env,
        aa: std.mem.Allocator,
        cfg_grove: *const cfg.file.Grove,
        tree: *Tree,
        node_stack: Stack = .{},
        file_count: usize = 0,

        pub fn init(env: Env, aa: std.mem.Allocator, cfg_grove: *const cfg.file.Grove, tree: *Tree) Cb {
            return Cb{
                .env = env,
                .aa = aa,
                .cfg_grove = cfg_grove,
                .tree = tree,
            };
        }
        pub fn deinit(my: *My) void {
            my.node_stack.deinit(my.env.a);
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

                    const entry = try my.tree.addChild(rubr.slc.last(my.node_stack.items));
                    const n = entry.data;
                    n.* = Node{ .a = my.env.a };
                    n.type = node_type;
                    n.path = try my.aa.dupe(u8, path);

                    try my.node_stack.append(my.env.a, entry.id);
                },
                walker.Kind.Leave => {
                    _ = my.node_stack.pop();
                },
                walker.Kind.File => {
                    const offsets = maybe_offsets orelse return error.ExpectedOffsets;
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

                        const entry = try my.tree.addChild(rubr.slc.last(my.node_stack.items));
                        const n = entry.data;
                        n.* = Node{ .a = my.env.a };
                        n.type = Node.Type.File;
                        n.path = try my.aa.dupe(u8, path);
                        n.language = language;
                        {
                            var readbuf: [1024]u8 = undefined;
                            var reader = file.reader(my.env.io, &readbuf);
                            n.content = try reader.interface.readAlloc(my.aa, stat.size);
                        }
                        n.grove_id = my.cfg_grove.id;

                        var parser = try mero.Parser.init(my.env.a, entry.id, my.tree);
                        try parser.parse();
                    } else {
                        try my.env.log.warning("Unsupported extension '{s}' for '{}' '{s}'\n", .{ my_ext, dir, path });
                    }
                },
            }
        }
    };

    // Distribute parent org_amps and agg_amps from root to leaf into agg_amps
    fn aggregateAmps(self: *Self) !void {
        var cb = struct {
            const My = @This();

            env: Env,
            tree: *Tree,
            defmgr: *const amp.DefMgr,

            update_count: u64 = 0,

            pub fn call(my: *My, entry: Tree.Entry) !void {
                const n = entry.data;

                if (rubr.slc.is_empty(n.org_amps.items))
                    return;

                if (my.parent(entry.id)) |parent_node| {
                    try my.inject_metadata(parent_node, n);
                }

                for (n.org_amps.items) |org| {
                    const def = org.ix.cptr(my.defmgr.defs.items);
                    if (def.location) |location| {
                        if (org.is_dependency) {
                            const def_node = my.tree.get(location.node_id) catch continue;
                            try my.inject_metadata(n, def_node);
                        } else {
                            const def_node = my.tree.cget(location.node_id) catch continue;
                            try my.inject_metadata(def_node, n);
                        }
                    }
                }

                for (n.agg_amps.items) |agg| {
                    const def = agg.cptr(my.defmgr.defs.items);
                    if (def.location) |location| {
                        const def_node = my.tree.cget(location.node_id) catch continue;
                        try my.inject_metadata(def_node, n);
                    }
                }
            }

            fn inject_metadata(my: *My, src: *const Node, dst: *Node) !void {
                // Inject src.orgs into dst.aggs, making sure only the last is inserted for each different template
                for (src.org_amps.items, 0..) |src_org, ix0| {
                    var is_last_of_kind: bool = true;
                    {
                        // &todo: Move to function, maybe create some helper util to convert between Node.DefIx and amp.Def
                        // &perf: Maybe keep track of the last amp per template kind?
                        // Check if there is another amp with the same template. If so, we take that.
                        const src_org_def = src_org.ix.cget(my.defmgr.defs.items) orelse continue;
                        if (src_org_def.template) |src_template| {
                            if (ix0 + 1 < src.org_amps.items.len) {
                                for (src.org_amps.items[ix0 + 1 ..]) |other_src_org| {
                                    const other_src_org_def = other_src_org.ix.cget(my.defmgr.defs.items) orelse continue;
                                    if (other_src_org_def.template) |other_src_template| {
                                        if (other_src_template.eql(src_template)) {
                                            is_last_of_kind = false;
                                            break;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if (is_last_of_kind and !my.is_present(dst, src_org.ix)) {
                        try dst.agg_amps.append(my.env.a, src_org.ix);
                        my.update_count += 1;
                    }
                }

                // Inject src.aggs into dst.aggs
                for (src.agg_amps.items) |src_agg_ix| {
                    if (!my.is_present(dst, src_agg_ix)) {
                        try dst.agg_amps.append(my.env.a, src_agg_ix);
                        my.update_count += 1;
                    }
                }
            }

            fn is_present(my: My, node: *const Node, needle: Node.DefIx) bool {
                for (node.org_amps.items) |org| {
                    if (org.ix.ix == needle.ix)
                        return true;
                    // Orgs block all template data with the same key
                    const needle_def = needle.cget(my.defmgr.defs.items) orelse return false;
                    const org_def = org.ix.cget(my.defmgr.defs.items) orelse return false;
                    if (needle_def.template) |needle_template| {
                        if (org_def.template) |org_template| {
                            if (needle_template.eql(org_template)) {
                                return true;
                            }
                        }
                    }
                }
                for (node.agg_amps.items) |agg| {
                    if (agg.ix == needle.ix)
                        return true;
                }
                return false;
            }

            fn parent(my: My, child_id: usize) ?*const Node {
                var id = child_id;
                while (my.tree.parent(id) catch unreachable) |pentry| {
                    if (!rubr.slc.is_empty(pentry.data.org_amps.items)) {
                        return pentry.data;
                    }
                    id = pentry.id;
                }
                return null;
            }
        }{ .env = self.env, .tree = &self.tree, .defmgr = &self.defmgr };

        const n = 10;
        for (0..n) |ix| {
            cb.update_count = 0;
            try self.tree.dfsAll(true, &cb);
            if (cb.update_count == 0)
                break;
            if (ix + 1 == n) {
                try self.env.stderr.print("Did not converge after {} iterations\n", .{n});
                return error.TooManyIterations;
            }
        }
    }

    fn createChores(self: *Self) !void {
        var cb = struct {
            const My = @This();

            chores: *Chores,
            tree: *const Tree,
            defmgr: *const amp.DefMgr,

            pub fn call(my: *My, entry: Tree.Entry) !void {
                _ = try my.chores.add(entry.id, my.tree, my.defmgr.*);
            }
        }{ .chores = &self.chores, .tree = &self.tree, .defmgr = &self.defmgr };
        try self.tree.dfsAll(true, &cb);
    }

    // Setup Node.org_amps and amp.DefMgr for data found in Node.line.terms
    fn resolveAmps(self: *Self) !void {
        var cb = struct {
            const My = @This();

            env: Env,
            aa: std.mem.Allocator,
            tree: *const Tree,
            defmgr: *amp.DefMgr,

            terms: *const Terms = undefined,
            path: []const u8 = &.{},
            grove_id: ?usize = null,
            is_new_file: bool = false,

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
                            return error.ExpectedGroveId;
                        my.grove_id = n.grove_id;
                        my.is_new_file = true;

                        if (amp.Date.findDate(my.path, .{ .strict_end = false, .allow_yyyy = false })) |date| {
                            var w = std.Io.Writer.Allocating.init(my.aa);
                            defer w.deinit();
                            try w.writer.print("&:s:{f}", .{date});
                            const content = try w.toOwnedSlice();
                            var strange = rubr.strng.Strange{ .content = content };
                            var path = try amp.Path.parse(&strange, my.env.a) orelse return error.CouldNotParseAmp;
                            defer path.deinit();
                            const grove_id = my.grove_id orelse return error.ExpectedGroveId;
                            if (try my.defmgr.resolve(&path, grove_id)) |amp_ix| {
                                try n.org_amps.append(my.env.a, .{ .ix = amp_ix, .pos = .{} });
                            } else {
                                try my.env.log.warning("Could not resolve amp '{f}' in '{s}'\n", .{ path, my.path });
                            }
                        }
                    },
                    else => {
                        defer my.is_new_file = false;

                        var line: usize = n.content_rows.begin;
                        var cols: rubr.idx.Range = .{};
                        for (n.line.terms_ixr.begin..n.line.terms_ixr.end) |term_ix| {
                            const term = &my.terms.items[term_ix];
                            cols.begin = cols.end;
                            cols.end += term.word.len;

                            if (term.kind == Term.Kind.Amp or term.kind == Term.Kind.Checkbox or term.kind == Term.Kind.Capital) {
                                var strange = rubr.strng.Strange{ .content = term.word };
                                var path = try amp.Path.parse(&strange, my.env.a) orelse return error.CouldNotParseAmp;
                                defer path.deinit();
                                if (!path.is_definition) {
                                    const grove_id = my.grove_id orelse return error.ExpectedGroveId;
                                    if (try my.defmgr.resolve(&path, grove_id)) |defix| {
                                        const def = Node.Def{ .ix = defix, .pos = .{ .row = line, .cols = cols }, .is_dependency = path.is_dependency };
                                        try n.org_amps.append(my.env.a, def);

                                        if (my.is_new_file and n.type == .Paragraph) {
                                            // Push org amps on the first (non-title) line to the file level. For _amp.md, also to the folder level.
                                            if (try my.tree.parent(entry.id)) |file| {
                                                try file.data.org_amps.append(my.env.a, def);

                                                if (is_amp_md(file.data.path)) {
                                                    if (try my.tree.parent(file.id)) |folder| {
                                                        try folder.data.org_amps.append(my.env.a, def);
                                                    }
                                                }
                                            }
                                        }
                                    } else {
                                        try my.env.log.warning("Could not resolve amp '{f}' in '{s}'\n", .{ path, my.path });
                                    }
                                }
                            } else if (term.kind == Term.Kind.Newline) {
                                line += term.word.len;
                                cols = .{};
                            }
                        }
                    },
                }
            }
        }{
            .env = self.env,
            .aa = self.aral.allocator(),
            .tree = &self.tree,
            .defmgr = &self.defmgr,
        };
        try self.tree.dfsAll(true, &cb);
    }

    fn collectDefs(self: *Self) !void {
        // Expects Node.org_amps to still be empty
        var cb = struct {
            const My = @This();

            env: Env,
            tree: *Tree,
            defmgr: *amp.DefMgr,

            terms: ?*const Terms = null,
            path: []const u8 = &.{},
            is_new_file: bool = false,
            grove_id: ?usize = null,
            do_process_amp_md: bool = false,
            do_process_other: bool = true,

            pub fn call(my: *My, entry: Tree.Entry) !void {
                const n = entry.data;

                switch (n.type) {
                    // Node.Type.Grove => {},
                    Node.Type.Grove, Node.Type.Folder => {
                        my.path = n.path;
                        // Process '_amp.md' before other Files and Folders.
                        // The metadata in such a file will be copied to the Folder and must be present before any resolving occurs.
                        // Both making defs absolute or aggregation of AMPs require this.
                        for (my.tree.childIds(entry.id)) |child_id| {
                            const child = my.tree.ptr(child_id);
                            if (is_amp_md(child.path)) {
                                // Allow processing '_amp.md'
                                my.do_process_amp_md = true;
                                try my.tree.dfs(child_id, true, my);
                                my.do_process_amp_md = false;
                            }
                        }
                    },
                    Node.Type.File => {
                        defer my.path = n.path;
                        my.terms = &n.terms;
                        my.is_new_file = true;
                        my.grove_id = n.grove_id orelse return error.ExpectedGroveId;

                        my.do_process_other = if (is_amp_md(n.path)) my.do_process_amp_md else true;
                    },
                    else => {
                        if (my.do_process_other)
                            try my.processOther(entry);
                    },
                }
            }

            fn processOther(my: *My, entry: Tree.Entry) !void {
                const n = entry.data;
                std.debug.assert(n.org_amps.items.len == 0);
                std.debug.assert(n.type != Node.Type.Grove and n.type != Node.Type.Folder and n.type != Node.Type.File);

                defer my.is_new_file = false;

                // Search n.line for a def AMP
                var line: usize = n.content_rows.begin;
                var cols: rubr.idx.Range = .{};

                for (n.line.terms_ixr.begin..n.line.terms_ixr.end) |term_ix| {
                    const terms = my.terms orelse unreachable;
                    const term = &terms.items[term_ix];

                    cols.begin = cols.end;
                    cols.end += term.word.len;

                    if (term.kind == Term.Kind.Amp) {
                        var strange = rubr.strng.Strange{ .content = term.word };

                        var def_ap = try amp.Path.parse(&strange, my.env.a) orelse return error.CouldNotParseAmp;
                        defer def_ap.deinit();
                        if (def_ap.is_definition) {
                            if (n.def != null)
                                return error.OnlyOneDefAllowed;
                            // Make the def amp absolute, if necessary
                            if (!def_ap.is_absolute) {
                                var child_id = entry.id;
                                // Try to find parent def
                                const maybe_parent_def: ?amp.Path = block: while (true) {
                                    if (try my.tree.parent(child_id)) |parent| {
                                        if (parent.data.def) |d| {
                                            const pdef = d.ix.cptr(my.defmgr.defs.items);
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
                                    try my.env.log.warning("Could not find parent def for non-absolute '{f}', making it absolute as it is\n", .{def_ap});
                                    def_ap.is_absolute = true;
                                }
                            }

                            // Collect all defs in a separate struct
                            const grove_id = my.grove_id orelse return error.ExpectedGroveId;
                            const pos = filex.Pos{ .row = line, .cols = cols };
                            if (try my.defmgr.appendDef(def_ap, grove_id, my.path, entry.id, pos)) |amp_ix| {
                                n.def = .{ .ix = amp_ix, .pos = pos };
                                try n.org_amps.append(my.env.a, n.def.?);
                            } else {
                                try my.env.log.warning("Duplicate definition found in '{s}'\n", .{my.path});
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
                            // A def on the first line is copied to the File as well to ensure all Nodes in this subtree can find it as a parent
                            // If the file is '_amp.md', it is copied to the Folder as well
                            if (try my.tree.parent(entry.id)) |file| {
                                file.data.def = n.def;
                                try file.data.org_amps.insertSlice(my.env.a, 0, n.org_amps.items);

                                if (is_amp_md(file.data.path)) {
                                    if (try my.tree.parent(file.id)) |folder| {
                                        folder.data.def = n.def;
                                        try folder.data.org_amps.insertSlice(my.env.a, 0, n.org_amps.items);
                                    }
                                }
                            }
                        },
                        else => {},
                    }
                }
            }
        }{ .env = self.env, .tree = &self.tree, .defmgr = &self.defmgr };
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

fn is_amp_md(path: []const u8) bool {
    return std.mem.endsWith(u8, path, "_amp.md");
}
