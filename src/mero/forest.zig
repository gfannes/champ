const std = @import("std");

const Term = @import("dto.zig").Term;
const Terms = @import("dto.zig").Terms;
const Tree = @import("dto.zig").Tree;
const Node = @import("dto.zig").Node;
const cfg = @import("../cfg.zig");
const cli = @import("../cli.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");

const Log = @import("rubr").log.Log;
const walker = @import("rubr").walker;
const slice = @import("rubr").slice;
const strings = @import("rubr").strings;
const Strange = @import("rubr").strange.Strange;

pub const Error = error{
    ExpectedOffsets,
    ExpectedAbsoluteDef,
    OnlyOneDefAllowed,
    ExpectedAtLeastOneGrove,
};

pub const Forest = struct {
    const Self = @This();

    log: *const Log,
    tree: Tree,
    a: std.mem.Allocator,

    pub fn init(log: *const Log, a: std.mem.Allocator) Self {
        return Self{ .log = log, .tree = Tree.init(a), .a = a };
    }
    pub fn deinit(self: *Self) void {
        var cb = struct {
            pub fn call(_: *@This(), entry: Tree.Entry) !void {
                entry.data.deinit();
            }
        }{};
        self.tree.each(&cb) catch {};
        self.tree.deinit();
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
    }

    pub fn findFile(self: *Self, name: []const u8) ?*mero.Node {
        for (self.tree.root_ids.items) |root_id| {
            if (self.findFile_(name, root_id)) |file| return file;
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

    fn collectDefs(self: *Self) !void {
        // Expects Node.orgs to still be empty
        var cb = struct {
            const My = @This();

            tree: *Tree,
            log: *const Log,
            a: std.mem.Allocator,

            terms: ?*const Terms = null,
            path: []const u8 = &.{},

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
                    },
                    else => {
                        // Search n.line for a def amp
                        for (n.line.terms_ixr.begin..n.line.terms_ixr.end) |term_ix| {
                            const terms = my.terms orelse unreachable;
                            const term = &terms.items[term_ix];
                            if (term.kind == Term.Kind.Amp) {
                                var strange = Strange{ .content = term.word };

                                var path = try amp.Path.parse(&strange, my.a);
                                if (path.is_definition) {
                                    if (n.orgs.items.len > 0)
                                        return Error.OnlyOneDefAllowed;
                                    std.debug.print("Found def '{}'\n", .{path});
                                    try n.orgs.append(path);
                                } else {
                                    path.deinit();
                                }
                            }
                        }

                        // Make the def amp absolute, if necessary
                        if (slice.first_ptr(n.orgs.items)) |def| {
                            if (!def.is_absolute) {
                                var child_id = entry.id;
                                const maybe_parent_def: ?amp.Path = block: while (true) {
                                    if (try my.tree.parent(child_id)) |parent| {
                                        if (slice.first(parent.data.orgs.items)) |pdef| {
                                            std.debug.assert(pdef.is_absolute);
                                            break :block pdef;
                                        } else {
                                            child_id = parent.id;
                                        }
                                    }
                                    break :block null;
                                };
                                if (maybe_parent_def) |parent_def|
                                    try def.prepend(parent_def);
                            }
                        }
                    },
                }
            }
        }{ .tree = &self.tree, .log = self.log, .a = self.a };
        try self.tree.dfsAll(true, &cb);
    }

    fn findFile_(self: *Self, name: []const u8, parent_id: Tree.Id) ?*mero.Node {
        const n = self.tree.ptr(parent_id);
        switch (n.type) {
            mero.Node.Type.File => if (std.mem.endsWith(u8, n.path, name)) return n,
            mero.Node.Type.Folder, mero.Node.Type.Grove => for (self.tree.childIds(parent_id)) |child_id| {
                if (self.findFile_(name, child_id)) |file| return file;
            },
            else => {},
        }
        return null;
    }
};
