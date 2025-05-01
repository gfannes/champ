const std = @import("std");

const File = @import("dto.zig").File;
const Term = @import("dto.zig").Term;
const Terms = @import("dto.zig").Terms;
const Tree = @import("dto.zig").Tree;
const Node = @import("dto.zig").Node;
const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");

const Log = @import("rubr").log.Log;
const walker = @import("rubr").walker;
const slice = @import("rubr").slice;
const strings = @import("rubr").strings;

pub const Error = error{
    ExpectedOffsets,
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

    pub fn loadGrove(self: *Self, cfg_grove: *const cfg.Grove) !void {
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

                        std.debug.print("Parsing '{s}'\n", .{path});
                        try parser.parse();
                    } else {
                        try my.log.warning("Unsupported extension '{s}' for '{}' '{s}'\n", .{ my_ext, dir, path });
                    }
                },
            }
        }
    };

    pub fn findFile(self: Self, filename: []const u8) ?*const File {
        // &impl
        _ = self;
        _ = filename;
        return null;
    }
};
