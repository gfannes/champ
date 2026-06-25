const std = @import("std");

const dto = @import("dto.zig");
const Term = dto.Term;
const Terms = dto.Terms;
const Tree = dto.Tree;
const Node = dto.Node;
const Text = dto.Text;
const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");
const chorex = @import("../chorex.zig");
const filex = @import("../filex.zig");

const rubr = @import("../rubr.zig");
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
    ExpectedConfigDefault,
};

pub const Forest = struct {
    const Self = @This();

    env: Env,
    aral: std.heap.ArenaAllocator = undefined,
    valid: bool = false,
    tree: Tree = undefined,
    defmgr: amp.DefMgr = undefined,
    chores: chorex.Chores = undefined,

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
        self.defmgr = amp.DefMgr.init(self.env, "?");
        self.chores = chorex.Chores.init(self.env);
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

    pub fn load(self: *Self, config: *const cfg.file.Config) !void {
        const selected_groves = config.selected_groves orelse return error.ExpectedConfigDefault;
        if (rubr.slc.isEmpty(selected_groves))
            return error.ExpectedAtLeastOneGrove;

        for (config.groves) |cfg_grove| {
            if (strings.contains(u8, selected_groves, cfg_grove.name))
                try self.loadGrove(&cfg_grove);
        }

        // &todo: Measure/print performance

        try self.createDefs();

        try self.resolveAmps();

        try self.aggregateAmps();

        try self.createChores();

        try self.computeChores();

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
        var cb = struct {
            const My = @This();
            const Stack = std.ArrayList(usize);

            env: Env,
            aa: std.mem.Allocator,
            cfg_grove: *const cfg.file.Grove,
            tree: *Tree,

            node_stack: Stack = .empty,
            file_count: usize = 0,

            pub fn deinit(my: *My) void {
                my.node_stack.deinit(my.env.a);
            }

            pub fn call(my: *My, dir: std.Io.Dir, filepath: []const u8, maybe_offsets: ?walker.Offsets, kind: walker.Kind) !void {
                switch (kind) {
                    .Enter => {
                        var name: []const u8 = undefined;
                        var node_type: Node.Type = undefined;
                        if (maybe_offsets) |offsets| {
                            name = filepath[offsets.name..];
                            node_type = .folder;
                        } else {
                            name = "<ROOT>";
                            node_type = .grove;
                        }

                        const entry = try my.tree.addChild(rubr.slc.last(my.node_stack.items));
                        const n = entry.data;
                        n.* = Node{ .a = my.env.a };
                        n.type = node_type;
                        n.filepath = try my.aa.dupe(u8, filepath);

                        try my.node_stack.append(my.env.a, entry.id);
                    },
                    .Leave => {
                        if (my.node_stack.pop()) |folder_id| {
                            const sort_files = true;
                            if (sort_files) {
                                const file_ids = my.tree.childIdsMut(folder_id);
                                const Ftor = struct {
                                    pub fn lt(m: *const My, a: Tree.Id, b: Tree.Id) bool {
                                        // &perf: this uses the full filepath while we know that only the filename itself differs
                                        return std.mem.lessThan(u8, m.tree.cptr(a).filepath, m.tree.cptr(b).filepath);
                                    }
                                };
                                std.sort.block(
                                    Tree.Id,
                                    file_ids,
                                    my,
                                    Ftor.lt,
                                );
                            }
                        }
                    },
                    .File => {
                        const offsets = maybe_offsets orelse return error.ExpectedOffsets;
                        const name = filepath[offsets.name..];

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

                            const file = try dir.openFile(my.env.io, name, .{});
                            defer file.close(my.env.io);

                            const stat = try file.stat(my.env.io);
                            const size_is_ok = if (my.cfg_grove.max_size) |max_size| stat.size < max_size else true;
                            if (!size_is_ok)
                                return;

                            var file_nid: usize = undefined;
                            {
                                const entry = try my.tree.addChild(rubr.slc.last(my.node_stack.items));
                                file_nid = entry.id;
                                const n = entry.data;
                                n.* = Node{
                                    .a = my.env.a,
                                    .type = .{ .file = .{ .language = language } },
                                    .filepath = try my.aa.dupe(u8, filepath),
                                    .grove_id = my.cfg_grove.id,
                                };
                                {
                                    var readbuf: [1024]u8 = undefined;
                                    var reader = file.reader(my.env.io, &readbuf);
                                    n.content = try reader.interface.readAlloc(my.aa, stat.size);
                                }
                            }

                            var parser = try mero.Parser.init(my.env.a, file_nid, my.tree);
                            try parser.parse();

                            // Switch from Text.ixr to Text.terms
                            const cb2 = struct {
                                terms: []const Term,
                                pub fn call(my2: @This(), e: Tree.Entry, before: bool) !void {
                                    if (!before)
                                        return;
                                    var n2 = e.data;
                                    switch (n2.type) {
                                        .text => |*text| {
                                            const ixr = text.terms.ixr;
                                            text.terms = .{ .slice = my2.terms[ixr.begin..ixr.end] };
                                        },
                                        else => {},
                                    }
                                }
                            }{ .terms = my.tree.cptr(file_nid).type.file.terms.items };
                            try my.tree.dfs(file_nid, &cb2);
                        } else {
                            try my.env.log.warning("Unsupported extension '{s}' for '{}' '{s}'\n", .{ my_ext, dir, filepath });
                        }
                    },
                }
            }
        }{ .env = self.env, .aa = self.aral.allocator(), .cfg_grove = cfg_grove, .tree = &self.tree };
        defer cb.deinit();

        var dir = std.Io.Dir.openDirAbsolute(self.env.io, cfg_grove.filepath, .{}) catch |err| {
            try self.env.log.err("Could not open grove folder '{s}'.\n", .{cfg_grove.filepath});
            return err;
        };
        defer dir.close(self.env.io);

        var w = walker.Walker{ .env = self.env };
        defer w.deinit();
        try w.walk(dir, &cb);
    }

    // Distribute parent org_amps and agg_amps from root to leaf into agg_amps
    fn aggregateAmps(self: *Self) !void {
        var cb = struct {
            const My = @This();

            env: Env,
            tree: *Tree,
            defmgr: *const amp.DefMgr,

            update_count: u64 = 0,

            pub fn call(my: *My, entry: Tree.Entry, before: bool) !void {
                if (!before)
                    return;

                const n = entry.data;

                if (rubr.slc.isEmpty(n.org_amps.items)) {
                    // std.debug.print("No orgs for {}\n", .{entry.id});
                    return;
                }
                // Tree-based inheritance between Nodes
                if (my.parent(entry.id)) |parent_entry| {
                    try my.injectAmps(parent_entry.data, n);
                }

                // For orgs that resolve to a named Def, inherit Tags.
                // The direction of inheritance depends on org.is_dependency.
                for (n.org_amps.items) |org| {
                    const def = org.ix.cptr(my.defmgr.defs.items);
                    if (def.location) |location| {
                        if (org.is_dependency) {
                            const def_node = my.tree.get(location.node_id) catch continue;
                            try my.injectAmps(n, def_node);
                        } else {
                            const def_node = my.tree.cget(location.node_id) catch continue;
                            try my.injectAmps(def_node, n);
                        }
                    }
                }

                // Inherite Tags from aggs that resolve to a named Def.
                for (n.agg_amps.items) |agg| {
                    const def = agg.cptr(my.defmgr.defs.items);
                    if (def.location) |location| {
                        const def_node = my.tree.cget(location.node_id) catch continue;
                        try my.injectAmps(def_node, n);
                    }
                }
            }

            fn injectAmps(my: *My, src: *const Node, dst: *Node) !void {
                // Inject src.orgs into dst.aggs
                for (src.org_amps.items) |src_org| {
                    if (!is_present(dst, src_org.ix)) {
                        try dst.agg_amps.append(my.env.a, src_org.ix);
                        my.update_count += 1;
                    }
                }

                // Inject src.aggs into dst.aggs
                for (src.agg_amps.items) |src_agg_ix| {
                    if (!is_present(dst, src_agg_ix)) {
                        try dst.agg_amps.append(my.env.a, src_agg_ix);
                        my.update_count += 1;
                    }
                }
            }

            fn is_present(node: *const Node, needle: Node.DefIx) bool {
                for (node.org_amps.items) |org| {
                    if (org.ix.ix == needle.ix)
                        return true;
                }
                for (node.agg_amps.items) |agg| {
                    if (agg.ix == needle.ix)
                        return true;
                }
                return false;
            }

            fn parent(my: My, child_id: usize) ?Tree.Entry {
                var id = child_id;
                while (my.tree.parent(id) catch unreachable) |pentry| {
                    if (!rubr.slc.isEmpty(pentry.data.org_amps.items)) {
                        return pentry;
                    }
                    id = pentry.id;
                }
                return null;
            }
        }{ .env = self.env, .tree = &self.tree, .defmgr = &self.defmgr };

        // We aggregate data several times to allow non-tree-based dependencies to reach all reachable nodes
        const n = 10;
        for (0..n) |ix| {
            cb.update_count = 0;
            try self.tree.dfsAll(&cb);
            if (cb.update_count == 0)
                break;
            if (ix + 1 == n) {
                try self.env.stderr.print("Did not converge after {} iterations\n", .{n});
                return error.TooManyIterations;
            }
        }
    }

    fn createChores(self: *Self) !void {
        for (self.defmgr.defs.items) |*def| {
            if (def.location) |location| {
                def.chore_id = try self.chores.create(def, location.node_id, &self.tree);
            }
        }
    }

    fn computeChores(self: *Self) !void {
        for (self.defmgr.defs.items) |def| {
            if (def.location) |location| {
                const node = self.tree.cptr(location.node_id);
                if (def.chore_id) |chore_id| {
                    for (node.org_amps.items) |org| {
                        const org_def = org.ix.cptr(self.defmgr.defs.items);
                        try self.chores.update(chore_id, org_def);
                    }
                    for (node.agg_amps.items) |agg| {
                        const agg_def = agg.cptr(self.defmgr.defs.items);
                        try self.chores.update(chore_id, agg_def);
                    }
                }
            }
        }
    }

    // Setup Node.org_amps and amp.DefMgr for data found in Node.line.terms
    fn resolveAmps(self: *Self) !void {
        var cb = struct {
            const My = @This();

            env: Env,
            aa: std.mem.Allocator,
            tree: *const Tree,
            defmgr: *amp.DefMgr,

            filepath: []const u8 = &.{},
            grove_id: ?usize = null,
            is_new_file: bool = false,

            pub fn call(my: *My, entry: Tree.Entry, before: bool) !void {
                if (!before)
                    return;

                const n = entry.data;
                switch (n.type) {
                    .grove => {},
                    .folder => {
                        my.filepath = n.filepath;
                    },
                    .file => {
                        my.filepath = n.filepath;
                        if (n.grove_id == null)
                            return error.ExpectedGroveId;
                        my.grove_id = n.grove_id;
                        my.is_new_file = true;

                        // &meta Move this to createDefs()
                        // Create a Def for a filepath that contains a date (or other metadata)
                        // if (amp.Date.findDate(my.filepath, .{ .strict_end = false, .allow_yyyy = false })) |date| {
                        //     var w = std.Io.Writer.Allocating.init(my.aa);
                        //     defer w.deinit();
                        //     try w.writer.print("&:s:{f}", .{date});
                        //     const content = try w.toOwnedSlice();
                        //     var strange = rubr.strng.Strange{ .content = content };
                        //     // &meta Create a phony Def and add the date to it
                        //     var meta = amp.Meta{ .a = my.env.a };
                        //     var path = amp.Path.parse(&strange, &meta) catch |err| {
                        //         try my.env.log.err("Could not parse amp from filepath '{s}' {}\n", .{ my.filepath, err });
                        //         return err;
                        //     };
                        //     defer path.deinit();
                        //     const grove_id = my.grove_id orelse return error.ExpectedGroveId;
                        //     if (try my.defmgr.resolve(&path, grove_id)) |amp_ix| {
                        //         try n.org_amps.append(my.env.a, .{ .ix = amp_ix, .pos = .{} });
                        //     } else {
                        //         try my.env.log.warning("Could not resolve amp '{f}' in '{s}'\n", .{ path, my.filepath });
                        //     }
                        // }
                    },
                    .text => |text| {
                        defer my.is_new_file = false;

                        var line: usize = n.content_rows.begin;
                        var cols: rubr.idx.Range = .{};

                        var meta = amp.Meta{ .a = my.env.a };
                        defer meta.deinit();
                        for (text.terms.slice) |term| {
                            cols.begin = cols.end;
                            cols.end += term.word.len;

                            if (term.kind == .Amp or term.kind == .Wikilink or term.kind == .Checkbox or term.kind == .Capital) {
                                var strange = rubr.strng.Strange{ .content = term.word };
                                // &meta Parse term for amp.Path and amp.Meta
                                if (amp.parse(&strange, &meta)) |maybe_ap_| {
                                    var maybe_path = maybe_ap_;
                                    if (maybe_path) |*path| {
                                        defer path.deinit();
                                        if (!path.is_definition) {
                                            const grove_id = my.grove_id orelse return error.ExpectedGroveId;
                                            if (try my.defmgr.resolve(path, grove_id)) |defix| {
                                                const def = Node.Def{ .ix = defix, .pos = .{ .row = line, .cols = cols }, .is_dependency = path.is_dependency };
                                                try n.org_amps.append(my.env.a, def);

                                                if (my.is_new_file and n.type.isText(.Paragraph)) {
                                                    // Push org amps on the first (non-title) line to the file level. For &.md, also to the folder level.
                                                    if (try my.tree.parent(entry.id)) |file| {
                                                        try file.data.org_amps.append(my.env.a, def);

                                                        if (amp.is_folder_metadata_fp(file.data.filepath)) {
                                                            if (try my.tree.parent(file.id)) |folder| {
                                                                try folder.data.org_amps.append(my.env.a, def);
                                                            }
                                                        }
                                                    }
                                                }
                                            } else {
                                                try my.env.log.warning("Could not resolve amp '{f}' in '{s}'\n", .{ path, my.filepath });
                                            }
                                        }
                                    }
                                } else |err| {
                                    try my.env.log.warning("Could not parse amp in '{s}':{} {}\n", .{ my.filepath, line, err });
                                    continue;
                                }
                            } else if (term.kind == .Newline) {
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
        try self.tree.dfsAll(&cb);
    }

    fn createDefs(self: *Self) !void {
        // Expects Node.org_amps to still be empty
        var cb = struct {
            const My = @This();

            env: Env,
            tree: *Tree,
            defmgr: *amp.DefMgr,

            filepath: []const u8 = &.{},
            is_new_file: bool = false,
            grove_id: ?usize = null,
            do_process_amp_md: bool = false,
            do_process_other: bool = true,

            pub fn call(my: *My, entry: Tree.Entry, before: bool) !void {
                if (!before)
                    return;

                const n = entry.data;

                switch (n.type) {
                    .grove, .folder => {
                        my.filepath = n.filepath;
                        // Process '&.md' before other Files and Folders.
                        // The metadata in such a file will be copied to the Folder and must be present before any resolving occurs.
                        // Both making defs absolute or aggregation of AMPs require this.
                        for (my.tree.childIds(entry.id)) |child_id| {
                            const child = my.tree.ptr(child_id);
                            if (amp.is_folder_metadata_fp(child.filepath)) {
                                // Allow processing '&.md'
                                my.do_process_amp_md = true;
                                try my.tree.dfs(child_id, my);
                                my.do_process_amp_md = false;
                            }
                        }
                    },
                    .file => {
                        defer my.filepath = n.filepath;
                        my.is_new_file = true;
                        my.grove_id = n.grove_id orelse return error.ExpectedGroveId;

                        my.do_process_other = if (amp.is_folder_metadata_fp(n.filepath)) my.do_process_amp_md else true;

                        // &wikilink: Add filepaths
                        if (false) {
                            if (std.mem.endsWith(u8, n.filepath, ".md")) {
                                var wiki_ap = amp.Path{ .a = my.env.a };
                                try wiki_ap.parts.append(wiki_ap.a, amp.Path.Part{ .content = n.filepath });
                                _ = try my.defmgr.appendDef(wiki_ap, n.grove_id.?, n.filepath, entry.id, .{});
                            }
                        }
                    },
                    .text => |text| {
                        if (my.do_process_other)
                            try my.processText(entry, text);
                    },
                }
            }

            fn processText(my: *My, entry: Tree.Entry, text: Text) !void {
                const n = entry.data;
                std.debug.assert(n.org_amps.items.len == 0);
                std.debug.assert(n.type != .grove and n.type != .folder and n.type != .file);

                defer my.is_new_file = false;

                // Search n.line for a def AMP
                var line: usize = n.content_rows.begin;
                var cols: rubr.idx.Range = .{};

                var needs_def: bool = false;
                var meta = amp.Meta{ .a = my.env.a };
                defer meta.deinit();
                for (text.terms.slice) |term| {
                    cols.begin = cols.end;
                    cols.end += term.word.len;

                    if (term.kind == .Amp or term.kind == .Checkbox or term.kind == .Capital) {
                        var strange = rubr.strng.Strange{ .content = term.word };

                        // &meta Parse both amp.Path and amp.Meta
                        // Also check other terms: captials, checkbox, ...
                        if (amp.parse(&strange, &meta)) |maybe_path_| {
                            var maybe_path = maybe_path_;
                            if (maybe_path) |*path| {
                                defer path.deinit();
                                if (path.is_definition) {
                                    if (n.def != null) {
                                        try my.env.stderr.print("Found more than one def in '{s}': {f} and {f}\n", .{ my.filepath, my.defmgr.get(n.def.?.ix).?.path, path });
                                        return error.OnlyOneDefAllowed;
                                    }

                                    // Make the def amp absolute, if necessary
                                    if (!path.is_absolute) {
                                        var child_id = entry.id;
                                        // Try to find parent def
                                        const maybe_parent_def: ?amp.Path = block: while (true) {
                                            if (try my.tree.parent(child_id)) |parent| {
                                                if (parent.data.def) |d| {
                                                    const pdef = d.ix.cptr(my.defmgr.defs.items);
                                                    break :block pdef.path;
                                                } else {
                                                    child_id = parent.id;
                                                }
                                            } else {
                                                break :block null;
                                            }
                                        };

                                        if (maybe_parent_def) |parent_def| {
                                            try path.prepend(parent_def);
                                            path.is_definition = true;
                                        } else {
                                            try my.env.log.warning("Could not find parent def for non-absolute '{f}' in '{s}', making it absolute as it is\n", .{ path, my.filepath });
                                            path.is_absolute = true;
                                        }
                                    }

                                    // Collect all defs in a separate struct
                                    const grove_id = my.grove_id orelse return error.ExpectedGroveId;
                                    const pos = filex.Pos{ .row = line, .cols = cols };
                                    if (try my.defmgr.appendDef(path.*, grove_id, my.filepath, entry.id, pos)) |amp_ix| {
                                        n.def = .{ .ix = amp_ix, .pos = pos };
                                        try n.org_amps.append(my.env.a, n.def.?);
                                    } else {
                                        try my.env.log.warning("Illegal or duplicate definition found in '{s}'\n", .{my.filepath});
                                    }
                                } else {
                                    needs_def = true;
                                }
                            } else {
                                // std.debug.print("Found metadata\n", .{});
                            }
                        } else |err| {
                            try my.env.log.warning("Could not parse amp in '{s}':{} {}\n", .{ my.filepath, line, err });
                            continue;
                        }
                    } else if (term.kind == .Newline) {
                        line += term.word.len;
                        cols = .{};
                    }
                }

                if (meta.hasData())
                    needs_def = true;

                if (n.def == null and needs_def) {
                    const grove_id = my.grove_id orelse return error.ExpectedGroveId;
                    const pos = filex.Pos{ .row = n.content_rows.begin };
                    n.def = .{ .ix = try my.defmgr.appendUnnamedDef(grove_id, my.filepath, entry.id, pos), .pos = pos };
                    // We add this Def to the org_amps as well to ensure aggregation picks it up
                    try n.org_amps.append(my.env.a, n.def.?);
                }

                if (n.def) |ref| {
                    var def = ref.ix.ptr(my.defmgr.defs.items);
                    try def.meta.update(meta);
                }

                if (my.is_new_file and n.type.isText(.Paragraph)) {
                    // A def on the first line is copied to the File as well to ensure all Nodes in this subtree can find it as a parent
                    // If the file is '&.md', it is copied to the Folder as well
                    if (try my.tree.parent(entry.id)) |file| {
                        file.data.def = n.def;
                        try file.data.org_amps.insertSlice(my.env.a, 0, n.org_amps.items);

                        if (amp.is_folder_metadata_fp(file.data.filepath)) {
                            if (try my.tree.parent(file.id)) |folder| {
                                folder.data.def = n.def;
                                try folder.data.org_amps.insertSlice(my.env.a, 0, n.org_amps.items);
                            }
                        }
                    }
                }
            }
        }{ .env = self.env, .tree = &self.tree, .defmgr = &self.defmgr };
        try self.tree.dfsAll(&cb);
    }

    fn findFile_(self: *Self, name: []const u8, id: Tree.Id) ?Tree.Entry {
        const n = self.tree.ptr(id);
        switch (n.type) {
            .file => {
                if (std.mem.endsWith(u8, n.filepath, name))
                    return Tree.Entry{ .id = id, .data = n };
            },
            .folder, .frove => {
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
