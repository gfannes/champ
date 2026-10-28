const std = @import("std");

const dto = @import("dto.zig");
const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");
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
    ExpectedConfigDefault,
    TextMustHaveParent,
    ParagraphMustHaveParent,
    FileMustHaveParent,
    ExpectedAmpNode,
    UnknownConfigurationData,
    FoundConfigurationDataOutsideMetadataFile,
    NoData,
};

pub const Forest = struct {
    const Self = @This();

    env: Env,
    aral: std.heap.ArenaAllocator = undefined,
    valid: bool = false,
    mero_tree: mero.Tree = undefined,
    amp_tree: amp.Tree = undefined,

    pub fn init(self: *Self) !void {
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
        self.mero_tree = mero.Tree.init(self.env.a);
        self.amp_tree = try amp.Tree.init(self.env.a);
    }
    pub fn deinit(self: *Self) void {
        var cb = struct {
            pub fn call(_: *@This(), entry: mero.Tree.Entry) !void {
                entry.data.deinit();
            }
        }{};
        self.mero_tree.each(&cb) catch {};
        self.mero_tree.deinit();
        self.amp_tree.deinit();
        self.aral.deinit();
    }
    pub fn reinit(self: *Self) !void {
        const env = self.env;

        self.deinit();

        self.* = Self{ .env = env };
        try self.init();
    }

    pub fn load(self: *Self, config: *const cfg.file.Config) !void {
        var s = try rubr.profile.Scope.start(self.env.io, .{ .ix = 0, .name = "loadGroves" });

        const selected_groves = config.selected_groves orelse return error.ExpectedConfigDefault;
        if (rubr.slc.isEmpty(selected_groves))
            return error.ExpectedAtLeastOneGrove;

        for (config.groves) |cfg_grove| {
            if (strings.contains(u8, selected_groves, cfg_grove.name))
                try self.loadGrove(&cfg_grove);
        }

        try s.mark(.{ .ix = 1, .name = "createDefs" });
        try self.createDefs();

        try s.mark(.{ .ix = 2, .name = "resolveAmps" });
        try self.resolveAmps();

        try s.mark(.{ .ix = 3, .name = "aggregateAmps" });
        try self.aggregateAmps();

        try s.mark(.{ .ix = 4, .name = "aggregateData" });
        try self.amp_tree.aggregateData();

        try s.stop();

        std.log.info("Duration measurements for loading and parsing the data:\n{f}", .{s});

        self.valid = true;
    }

    pub fn findFile(self: *Self, name: []const u8) ?mero.Tree.Entry {
        for (self.mero_tree.root_ids.items) |root_id| {
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
            tree: *mero.Tree,

            node_stack: Stack = .empty,
            file_count: usize = 0,

            pub fn deinit(my: *My) void {
                my.node_stack.deinit(my.env.a);
            }

            pub fn call(my: *My, dir: std.Io.Dir, filepath: []const u8, maybe_offsets: ?walker.Offsets, kind: walker.Kind) !void {
                switch (kind) {
                    .Enter => {
                        var name: []const u8 = undefined;
                        var node_type: mero.Node.Type = undefined;
                        if (maybe_offsets) |offsets| {
                            name = filepath[offsets.name..];
                            node_type = .folder;
                        } else {
                            name = "<ROOT>";
                            node_type = .{ .grove = .{ .id = my.cfg_grove.id orelse return error.ExpectedGroveId } };
                        }

                        const entry = try my.tree.addChild(rubr.slc.last(my.node_stack.items));
                        const n = entry.data;
                        n.* = mero.Node{ .a = my.env.a };
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
                                    pub fn lt(m: *const My, a: mero.Tree.Id, b: mero.Tree.Id) bool {
                                        // &perf: this uses the full filepath while we know that only the filename itself differs
                                        return std.mem.lessThan(u8, m.tree.cptr(a).filepath, m.tree.cptr(b).filepath);
                                    }
                                };
                                std.sort.block(
                                    mero.Tree.Id,
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
                                n.* = mero.Node{
                                    .a = my.env.a,
                                    .type = .{ .file = .{ .language = language } },
                                    .filepath = try my.aa.dupe(u8, filepath),
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
                                terms: []const mero.Term,
                                pub fn call(my2: @This(), e: mero.Tree.Entry, before: bool) !void {
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
                            std.log.warn("Unsupported extension '{s}' for '{}' '{s}'", .{ my_ext, dir, filepath });
                        }
                    },
                }
            }
        }{ .env = self.env, .aa = self.aral.allocator(), .cfg_grove = cfg_grove, .tree = &self.mero_tree };
        defer cb.deinit();

        var dir = std.Io.Dir.openDirAbsolute(self.env.io, cfg_grove.filepath, .{}) catch |err| {
            std.log.err("Could not open grove folder '{s}'.", .{cfg_grove.filepath});
            return err;
        };
        defer dir.close(self.env.io);

        var w = walker.Walker{ .env = self.env };
        defer w.deinit();
        try w.walk(dir, &cb);
    }

    // Distribute the dependencies and aggregate the metadata
    fn aggregateAmps(self: *Self) !void {
        try self.amp_tree.addAncestralDependencies();
        try self.amp_tree.aggregateDependencies();
    }

    fn resolveAmps(self: *Self) !void {
        var cb = struct {
            const My = @This();

            env: Env,
            aa: std.mem.Allocator,
            mero_tree: *const mero.Tree,
            amp_tree: *amp.Tree,

            filepath: []const u8 = &.{},
            grove_id: ?usize = null,
            is_new_file: bool = false,

            pub fn call(my: *My, entry: mero.Tree.Entry, before: bool) !void {
                if (!before)
                    return;

                const n = entry.data;
                switch (n.type) {
                    .grove => |grove| {
                        my.grove_id = grove.id;
                    },
                    .folder => {
                        my.filepath = n.filepath;
                    },
                    .file => {
                        my.filepath = n.filepath;
                        my.is_new_file = true;
                    },
                    .text => |text| {
                        defer my.is_new_file = false;

                        var line: usize = n.content_rows.begin;
                        var cols: rubr.idx.Range = .{};

                        var meta = amp.Meta{ .a = my.env.a };
                        defer meta.deinit();

                        var is_first_definition: bool = true;

                        for (text.terms.slice) |term| {
                            cols.begin = cols.end;
                            cols.end += term.word.len;

                            if (term.kind == .Amp or term.kind == .Wikilink or term.kind == .Checkbox or term.kind == .Capital) {
                                var strange = rubr.strng.Strange{ .content = term.word };
                                // &meta Parse term for amp.Path and amp.Meta
                                if (amp.parse(&strange, &meta)) |maybe_ap_| {
                                    var maybe_ap = maybe_ap_;
                                    if (maybe_ap) |*ap| {
                                        defer ap.deinit();

                                        if (ap.is_definition and is_first_definition) {
                                            // All non-first definitions will be treated as regular dependencies
                                            is_first_definition = false;
                                        } else if (ap.is_config) {
                                            // Nothing todo for configuration data here
                                        } else {
                                            const grove_id = my.grove_id orelse return error.ExpectedGroveId;

                                            const amp_node = (try my.amp_tree.resolve(ap.*, my.grove_id, my.filepath)) orelse rv: {
                                                std.log.debug("Could not resolve {f}", .{ap.*});
                                                break :rv try my.amp_tree.addPhony(ap.*);
                                            };
                                            if (n.amp_node) |n_amp_node| {
                                                if (ap.is_dependency) {
                                                    _ = try my.amp_tree.addAncestralDependency(amp_node, n_amp_node);
                                                } else {
                                                    _ = try my.amp_tree.addAncestralDependency(n_amp_node, amp_node);
                                                }
                                            }

                                            try my.amp_tree.addReference(amp_node, grove_id, entry.id, my.filepath, .{ .row = line, .cols = cols });
                                        }
                                    }
                                } else |err| {
                                    std.log.warn("Could not parse amp in '{s}':{} {}", .{ my.filepath, line, err });
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
            .mero_tree = &self.mero_tree,
            .amp_tree = &self.amp_tree,
        };
        try self.mero_tree.dfsAll(&cb);
    }

    fn createDefs(self: *Self) !void {
        var cb = struct {
            const My = @This();
            const Info = struct {
                const Kind = union(enum) {
                    folder: void,
                    file: []const u8, // filepath
                    text: void,
                };
                // Holds all info necessary to create an amp.Node in a late manner: only when this autodef info is not overridden by file/folder metadata.
                const AutodefStage = struct {
                    parent_id: ?amp.Tree.Id = null,
                    mero_id: mero.Tree.Id,
                    filepath: []const u8,
                };

                kind: Kind,

                autodef_stage: ?AutodefStage = null,

                is_metadata_file: bool = false,
                amp_node: ?amp.Tree.Id = null,
                autodef_from_folder: bool = false,
                autodef_from_file: bool = false,
                autodef_from_acronym: bool = false,
            };

            env: Env,
            mero_tree: *mero.Tree,
            amp_tree: *amp.Tree,

            filepath: []const u8 = &.{},
            is_file_metadata: bool = false,
            grove_id: ?usize = null,
            do_process_amp_md: bool = false,
            do_process_text: bool = true,

            info_path: std.ArrayList(Info) = .empty,

            fn deinit(my: *My) void {
                my.info_path.deinit(my.env.a);
            }

            pub fn call(my: *My, entry: mero.Tree.Entry, before: bool) !void {
                const n = entry.data;

                if (!before) {
                    my.is_file_metadata = false;
                    var info = my.info_path.pop();
                    if (info) |*i|
                        try my.commitAutodef(i);
                    return;
                }

                // Inherit all Info data except amp_node
                {
                    var info: Info = rubr.slc.last(my.info_path.items) orelse .{ .kind = .text };
                    info.amp_node = null;
                    try my.info_path.append(my.env.a, info);
                }
                const info: *Info = rubr.slc.lastPtrUnsafe(my.info_path.items);

                var meta = amp.Meta{ .a = my.env.a };
                defer meta.deinit();

                var amp_node: ?amp.Tree.Id = null;
                var push_to_parents: bool = false;
                defer {
                    if (amp_node) |an| {
                        if (n.amp_node == null)
                            n.amp_node = an;
                        my.setAmpNode(an, push_to_parents) catch {};
                        my.amp_tree.updateMeta(an, meta) catch {};
                    }
                }

                switch (n.type) {
                    .grove => |grove| {
                        my.grove_id = grove.id;
                    },
                    .folder => {
                        info.kind = .folder;

                        if (info.autodef_from_folder) {
                            info.autodef_stage = .{
                                .parent_id = my.parentAmpNode(),
                                .mero_id = entry.id,
                                .filepath = n.filepath,
                            };
                        }

                        my.filepath = n.filepath;

                        // Process '&.md' before other Files and Folders.
                        // The metadata in such a file will be copied to the Folder and must be present before any resolving occurs.
                        // Both making defs absolute or aggregation of AMPs require this.
                        for (my.mero_tree.childIds(entry.id)) |child_id| {
                            const child = my.mero_tree.ptr(child_id);
                            if (amp.is_folder_metadata_fp(child.filepath)) {
                                // Allow processing '&.md'
                                my.do_process_amp_md = true;
                                try my.mero_tree.dfs(child_id, my);
                                my.do_process_amp_md = false;
                            }
                        }

                        // Do not use `info` here: it might have moved in memory due to recursive call to my.mero_tree.dfs()
                        try my.commitAutodef(rubr.slc.lastPtrUnsafe(my.info_path.items));
                    },
                    .file => {
                        info.kind = .{ .file = n.filepath };
                        info.is_metadata_file = amp.is_folder_metadata_fp(n.filepath);

                        defer my.filepath = n.filepath;

                        // Set is_file_metadata to true when we start processing the text
                        defer my.is_file_metadata = true;
                        my.is_file_metadata = false;

                        my.do_process_text = if (amp.is_folder_metadata_fp(n.filepath)) my.do_process_amp_md else true;

                        var create_amp_node: bool = false;

                        // &wikilink: Add filepaths
                        if (false) {
                            if (std.mem.endsWith(u8, n.filepath, ".md")) {
                                var wiki_ap = amp.Path{ .a = my.env.a };
                                try wiki_ap.parts.append(wiki_ap.a, amp.Path.Part{ .content = n.filepath });
                            }
                        }

                        if (true) {
                            if (amp.Date.findDate(n.filepath, .{ .strict_end = false, .allow_yyyy = false })) |date| {
                                meta.date = date;
                            }
                        }

                        // &meta: check n.filepath for amp info
                        // - when it starts with a lowercase, it is a task that is still todo
                        // - use folder path as amp path

                        if (meta.hasData())
                            create_amp_node = true;

                        if (!info.is_metadata_file and info.autodef_from_file) {
                            info.autodef_stage = .{
                                .parent_id = my.parentAmpNode(),
                                .mero_id = entry.id,
                                .filepath = n.filepath,
                            };
                        }

                        if (info.autodef_stage == null and amp_node == null and create_amp_node) {
                            const grove_id = my.grove_id orelse return error.ExpectedGroveId;
                            const pos = filex.Pos{};
                            amp_node = try my.amp_tree.addUnnamed(my.parentAmpNode(), grove_id, entry.id, n.filepath, pos);
                        }
                    },
                    .text => |text| {
                        if (!my.do_process_text)
                            return;

                        if (my.is_file_metadata)
                            // Metadata in the first paragraph of a file is for that file
                            my.is_file_metadata = n.type.isText(.Paragraph);
                        defer my.is_file_metadata = false;
                        push_to_parents = my.is_file_metadata;

                        // Search n.line for a def AMP
                        var line: usize = n.content_rows.begin;
                        var cols: rubr.idx.Range = .{};

                        var create_amp_node: bool = false;
                        for (text.terms.slice) |term| {
                            cols.begin = cols.end;
                            cols.end += term.word.len;

                            if (term.kind == .Amp or term.kind == .Checkbox or term.kind == .Capital) {
                                create_amp_node = true;

                                var strange = rubr.strng.Strange{ .content = term.word };

                                // &meta Parse both amp.Path and amp.Meta
                                // Also check other terms: captials, checkbox, ...
                                if (amp.parse(&strange, &meta)) |maybe_ap_| {
                                    var maybe_ap = maybe_ap_;
                                    if (maybe_ap) |*ap| {
                                        defer ap.deinit();
                                        if (ap.is_config) {
                                            // &. contains configuration data
                                            std.log.info("Found configuration data {f}", .{ap.*});
                                            try my.setConfigurationData(ap.*);
                                        } else if (ap.is_definition) {
                                            // Make the amp.Path absolute if necessary
                                            if (!ap.is_absolute) {
                                                if (rubr.slc.getBackPtr(my.info_path.items, 1)) |parent_info| {
                                                    // If autodef_from_file is enabled and this is file metadata, we have to drop the staged info that might create an autodef amp_node later.
                                                    // Else, we create it now to ensure it is available to parentAmpNode()
                                                    if (push_to_parents and info.autodef_from_file)
                                                        parent_info.autodef_stage = null
                                                    else
                                                        try my.commitAutodef(parent_info);
                                                }
                                                if (rubr.slc.getBackPtr(my.info_path.items, 2)) |parent_info| {
                                                    // If autodef_from_file is enabled and this is file metadata, we have to drop the staged info that might create an autodef amp_node later.
                                                    // Else, we create it now to ensure it is available to parentAmpNode()
                                                    if (push_to_parents and info.autodef_from_file)
                                                        parent_info.autodef_stage = null
                                                    else
                                                        try my.commitAutodef(parent_info);
                                                }
                                                if (my.parentAmpNode()) |parent_id| {
                                                    var parent_ap = try my.amp_tree.ampPath(my.env.a, parent_id);
                                                    defer parent_ap.deinit();
                                                    try ap.prepend(parent_ap);
                                                    ap.is_definition = true;
                                                } else {
                                                    std.log.warn("Could not find parent def for non-absolute '{f}' in '{s}', making it absolute as it is", .{ ap, my.filepath });
                                                    ap.is_absolute = true;
                                                }
                                            }

                                            // Create an amp.Node in the amp.Tree for this mero.Node
                                            const grove_id = my.grove_id orelse return error.ExpectedGroveId;
                                            const pos = filex.Pos{ .row = line, .cols = cols };
                                            const an = try my.amp_tree.addAbsolute(ap.*, grove_id, entry.id, my.filepath, pos);
                                            if (amp_node == null)
                                                // The first definition is added to info_path, see hereunder via setAmpNode()
                                                amp_node = an;
                                        }
                                    }
                                } else |err| {
                                    std.log.warn("Could not parse amp in '{s}':{} {}", .{ my.filepath, line, err });
                                    continue;
                                }
                            } else if (term.kind == .Newline) {
                                line += term.word.len;
                                cols = .{};
                            }
                        }

                        if (amp_node == null and create_amp_node) {
                            const grove_id = my.grove_id orelse return error.ExpectedGroveId;
                            const pos = filex.Pos{ .row = n.content_rows.begin, .cols = n.content_cols };
                            amp_node = try my.amp_tree.addUnnamed(my.parentAmpNode(), grove_id, entry.id, my.filepath, pos);
                        }
                    },
                }
            }

            fn commitAutodef(my: *My, info: *Info) !void {
                if (info.autodef_stage) |*stage| {
                    if (info.amp_node == null) {
                        var ap: amp.Path = if (stage.parent_id) |parent_id|
                            try my.amp_tree.ampPath(my.env.a, parent_id)
                        else
                            amp.Path.init(my.env.a);
                        defer ap.deinit();
                        try ap.parts.append(ap.a, ampPartFromFilepath(stage.filepath));
                        ap.is_definition = true;
                        ap.is_absolute = true;

                        const grove_id = my.grove_id orelse return error.ExpectedGroveId;
                        const pos = filex.Pos{};
                        const amp_node = try my.amp_tree.addAbsolute(ap, grove_id, stage.mero_id, stage.filepath, pos);
                        const n = my.mero_tree.ptr(stage.mero_id);
                        if (n.amp_node == null)
                            n.amp_node = amp_node;
                        info.amp_node = amp_node;
                    }

                    info.autodef_stage = null;
                }
            }

            fn setAmpNode(my: *My, amp_node: amp.Tree.Id, push_to_parents: bool) !void {
                const top = rubr.slc.getBackPtr(my.info_path.items, 0) orelse return error.NoData;
                top.amp_node = amp_node;

                if (push_to_parents) {
                    const file = rubr.slc.getBackPtr(my.info_path.items, 1) orelse return error.NoData;
                    if (file.kind != .file)
                        return;

                    if (file.amp_node) |file_id|
                        // There is a direct (File) parent: add a dependency on it before we overwrite this entry in my.path
                        _ = try my.amp_tree.addAncestralDependency(amp_node, file_id);
                    // We use amp_node instead of the any pre-existing File amp.Node
                    file.amp_node = amp_node;

                    if (amp.is_folder_metadata_fp(file.kind.file)) {
                        const folder = rubr.slc.getBackPtr(my.info_path.items, 2) orelse return error.NoData;
                        if (folder.amp_node) |folder_id|
                            // There is a 2nd-order (Folder) parent: add a dependency on it before we overwrite this entry in my.path
                            _ = try my.amp_tree.addAncestralDependency(amp_node, folder_id);
                        // We use amp_node instead of the any pre-existing Folder amp.Node
                        folder.amp_node = amp_node;
                    }
                }
            }

            fn parentAmpNode(my: My) ?amp.Tree.Id {
                var rit = std.mem.reverseIterator(my.info_path.items);
                while (rit.next()) |info| {
                    if (info.amp_node) |amp_node|
                        return amp_node;
                }
                return null;
            }

            fn partIs(str: []const u8, ap: amp.Path, ix: usize) bool {
                if (ix >= ap.parts.items.len)
                    return false;
                return std.mem.eql(u8, ap.parts.items[ix].content, str);
            }

            fn setConfigurationData(my: *My, ap: amp.Path) !void {
                // We will directly store the configuration data into the Folder Info
                var maybe_folder_info: ?*Info = null;
                var rit = std.mem.reverseIterator(my.info_path.items);
                while (rit.nextPtr()) |info| {
                    if (info.kind == .file and !info.is_metadata_file)
                        // We only consider configuration data from a metadata file
                        break;
                    if (info.kind == .folder) {
                        maybe_folder_info = info;
                        break;
                    }
                }

                const folder_info = maybe_folder_info orelse return error.FoundConfigurationDataOutsideMetadataFile;

                if (partIs("autodef", ap, 0)) {
                    if (partIs("from_folder", ap, 1)) {
                        folder_info.autodef_from_folder = true;
                    } else if (partIs("from_file", ap, 1)) {
                        folder_info.autodef_from_file = true;
                    } else if (partIs("from_acronym", ap, 1)) {
                        folder_info.autodef_from_acronym = true;
                    } else {
                        return error.UnknownConfigurationData;
                    }
                } else {
                    return error.UnknownConfigurationData;
                }
            }

            fn ampPartFromFilepath(filepath: []const u8) amp.Path.Part {
                const start_ix = if (std.mem.findLast(u8, filepath, "/")) |ix| ix + 1 else 0;
                const end_ix = std.mem.find(u8, filepath, ".md") orelse filepath.len;
                return .{ .content = filepath[start_ix..end_ix] };
            }
        }{ .env = self.env, .mero_tree = &self.mero_tree, .amp_tree = &self.amp_tree };
        defer cb.deinit();
        try self.mero_tree.dfsAll(&cb);
    }

    fn findFile_(self: *Self, name: []const u8, id: mero.Tree.Id) ?mero.Tree.Entry {
        const n = self.mero_tree.ptr(id);
        switch (n.type) {
            .file => {
                if (std.mem.endsWith(u8, n.filepath, name))
                    return mero.Tree.Entry{ .id = id, .data = n };
            },
            .folder, .grove => {
                for (self.mero_tree.childIds(id)) |child_id| {
                    if (self.findFile_(name, child_id)) |file|
                        return file;
                }
            },
            else => {},
        }
        return null;
    }
};
