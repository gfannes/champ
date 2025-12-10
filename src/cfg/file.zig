const std = @import("std");
const rubr = @import("rubr");
const Env = rubr.Env;

// Loads Config from a file in ZON format
pub const Loader = struct {
    const Self = @This();
    const Hasher = std.crypto.hash.sha2.Sha256;
    const Hash = [Hasher.digest_length]u8;

    pub const What = enum { Config, Fui };

    config: ?Config = null,
    config_hash: ?Hash = null,

    fui: ?Fui = null,
    fui_hash: ?Hash = null,

    env: Env,
    aral: std.heap.ArenaAllocator,

    // We hold an std.heap.ArenaAllocator: do not move me once an ArenaAllocator.allocator() is created/used
    pub fn init(env: Env) !Self {
        return Self{ .env = env, .aral = std.heap.ArenaAllocator.init(env.a) };
    }
    pub fn deinit(self: *Self) void {
        self.aral.deinit();
    }

    // For some reason, std.zon.parse.fromSliceAlloc() expects a sentinel string
    // Returns true if the loaded config is different from before
    pub fn loadFromContent(self: *Self, content: [:0]const u8, what: What) !bool {
        var my_hash: Hash = undefined;
        Hasher.hash(content, &my_hash, .{});

        switch (what) {
            .Config => {
                if (self.config_hash) |hash| {
                    if (std.mem.eql(u8, &hash, &my_hash))
                        return false;
                }
                self.config = try std.zon.parse.fromSliceAlloc(Config, self.aral.allocator(), content, null, .{});
                self.config_hash = my_hash;

                try self.normalize();
            },
            .Fui => {
                if (self.fui_hash) |hash| {
                    if (std.mem.eql(u8, &hash, &my_hash))
                        return false;
                }
                self.fui = try std.zon.parse.fromSliceAlloc(Fui, self.aral.allocator(), content, null, .{});
                self.fui_hash = my_hash;
            },
        }

        return true;
    }

    pub fn loadFromFile(self: *Self, filename: []const u8, what: What) !bool {
        var file = try std.fs.openFileAbsolute(filename, .{});
        defer file.close();

        // For some reason, std.zon.parse.fromSliceAlloc() expects a sentinel string
        var readbuf: [1024]u8 = undefined;
        var reader = file.reader(self.env.io, &readbuf);
        const size = try reader.getSize();
        const content: [:0]u8 = try self.aral.allocator().allocSentinel(u8, size, 0);
        try reader.interface.readSliceAll(content);

        return try self.loadFromContent(content, what);
    }

    // - Rework include extensions from 'md' to '.md'
    fn normalize(self: *Self) !void {
        const a = self.aral.allocator();
        if (self.config) |config| {
            for (config.groves, 0..) |*grove, id| {
                grove.id = id;
                if (grove.include) |include| {
                    const new_include = try a.alloc([]const u8, include.len);
                    for (include, 0..) |ext, ix| {
                        new_include[ix] = if (ext.len > 0 and ext[0] != '.')
                            try std.mem.concat(a, u8, &[_][]const u8{ ".", ext })
                        else
                            ext;
                    }
                    grove.include = new_include;
                }
            }
        }
    }
};

pub const Grove = struct {
    id: ?usize = null,

    name: []const u8,
    path: []const u8,
    include: ?[][]const u8 = null,
    max_size: ?usize = null,
    max_count: ?usize = null,
};

pub const Lsp = struct {
    max_array_size: usize = 100,
};

pub const Config = struct {
    groves: []Grove = &.{},
    max_memsize: ?usize = null,
    default: ?[][]const u8 = null,
    lsp: Lsp = .{},
};

pub const Fui = struct {
    extra: ?[][]const u8 = null,
};

test "cfg" {
    const ut = std.testing;

    const content =
        \\.{
        \\    .max_memsize = 10_000_000_000,
        \\    .groves = .{
        \\        .{
        \\            .name = "am",
        \\            .path = "/home/geertf/am",
        \\            .include = .{ "md", "rb", "txt", "hpp", "cpp", "h", "c" },
        \\            .max_size = 256000,
        \\        },
        \\        .{
        \\            .name = "gat",
        \\            .path = "/home/geertf/gatenkaas",
        \\            .include = .{"md"},
        \\        },
        \\    },
        \\}
    ;

    var env_inst = Env.Instance{};
    env_inst.init();
    defer env_inst.deinit();

    var loader = try Loader.init(env_inst.env());
    defer loader.deinit();

    _ = try loader.loadFromContent(content, .Config);

    if (loader.config) |config| {
        try ut.expectEqual(10_000_000_000, config.max_memsize);

        try ut.expectEqual(2, config.groves.len);
        {
            const grove = config.groves[0];
            try ut.expectEqualSlices(u8, grove.name, "am");
            try ut.expectEqualSlices(u8, grove.path, "/home/geertf/am");
            try ut.expectEqual(grove.max_size, 256000);
        }
        {
            const grove = config.groves[1];
            try ut.expectEqualSlices(u8, grove.name, "gat");
            try ut.expectEqualSlices(u8, grove.path, "/home/geertf/gatenkaas");
            try ut.expectEqual(grove.max_size, null);
        }
    } else try ut.expect(false);
}
