const std = @import("std");
const rubr = @import("rubr");
const cli = @import("cli.zig");

// Main configuration
// '~/.config/champ/config.zon'
pub const Config = struct {
    groves: []Grove = &.{},
    max_memsize: ?usize = null,
    default: ?[][]const u8 = null,
    lsp: Lsp = .{},

    pub fn write(self: Config, parent: *rubr.naft.Node) void {
        var n = parent.node("Config");
        defer n.deinit();
        if (self.max_memsize) |max_memsize|
            n.attr("max_memsize", max_memsize);
        for (self.groves) |grove| {
            if (self.default) |wanted_groves| {
                if (!rubr.strings.contains(u8, wanted_groves, grove.name))
                    continue;
            }
            grove.write(&n);
        }
        self.lsp.write(&n);
    }
};
pub const Grove = struct {
    id: ?usize = null,

    name: []const u8,
    path: []const u8,
    include: ?[][]const u8 = null,
    max_size: ?usize = null,
    max_count: ?usize = null,
    autodef: bool = false,

    pub fn write(self: Grove, parent: *rubr.naft.Node) void {
        var n = parent.node("Grove");
        defer n.deinit();
        n.attr("name", self.name);
        n.attr("path", self.path);
        n.attr("autodef", self.autodef);
        if (self.max_size) |max_size|
            n.attr("max_size", max_size);
        if (self.max_count) |max_count|
            n.attr("max_count", max_count);
        if (self.include) |include| {
            var nn = n.node("Includes");
            defer nn.deinit();
            for (include) |inc|
                nn.attr1(inc);
        }
    }
};
pub const Lsp = struct {
    max_array_size: usize = 100,

    pub fn write(self: Lsp, parent: *rubr.naft.Node) void {
        var n = parent.node("Lsp");
        defer n.deinit();
        n.attr("max_array_size", self.max_array_size);
    }
};

// File-UI configuration
// '~/.config/champ/fui.zon'
pub const Fui = struct {
    extra: ?[][]const u8 = null,
};

// Loads Config from a file in ZON format
pub const Loader = struct {
    const Self = @This();
    const Hasher = std.crypto.hash.sha2.Sha256;
    const Hash = [Hasher.digest_length]u8;

    pub const What = enum { Config, Fui };

    env: rubr.Env,
    cli_args: *const cli.Args,

    config: ?Config = null,
    config_hash: ?Hash = null,

    fui: ?Fui = null,
    fui_hash: ?Hash = null,

    tmp_content: ?[:0]u8 = null,

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
                self.config = try std.zon.parse.fromSliceAlloc(Config, self.env.aa, content, null, .{});
                self.config_hash = my_hash;

                try self.normalize();

                if (self.cli_args.groves.items.len > 0)
                    // cli.Args.groves overrules Config.default
                    self.config.?.default = self.cli_args.groves.items;
            },
            .Fui => {
                if (self.fui_hash) |hash| {
                    if (std.mem.eql(u8, &hash, &my_hash))
                        return false;
                }
                self.fui = try std.zon.parse.fromSliceAlloc(Fui, self.env.aa, content, null, .{});
                self.fui_hash = my_hash;
            },
        }

        return true;
    }

    pub fn loadFromFile(self: *Self, filename: []const u8, what: What) !bool {
        var file = try std.Io.Dir.openFileAbsolute(self.env.io, filename, .{});
        defer file.close(self.env.io);

        // For some reason, std.zon.parse.fromSliceAlloc() expects a sentinel string
        var readbuf: [1024]u8 = undefined;
        var reader = file.reader(self.env.io, &readbuf);
        const size = try reader.getSize();

        // Avoid allocating this buffer each time: the LSP server loads the Config on a regular basis.
        if (self.tmp_content == null or self.tmp_content.?.len < size)
            self.tmp_content = try self.env.aa.allocSentinel(u8, size, 0);

        try reader.interface.readSliceAll(self.tmp_content.?);

        return try self.loadFromContent(self.tmp_content.?, what);
    }

    // - Rework include extensions from 'md' to '.md'
    fn normalize(self: *Self) !void {
        const aa = self.env.aa;
        if (self.config) |config| {
            for (config.groves, 0..) |*grove, id| {
                grove.id = id;
                if (grove.include) |include| {
                    const new_include = try aa.alloc([]const u8, include.len);
                    for (include, 0..) |ext, ix| {
                        new_include[ix] = if (ext.len > 0 and ext[0] != '.')
                            try std.mem.concat(aa, u8, &[_][]const u8{ ".", ext })
                        else
                            ext;
                    }
                    grove.include = new_include;
                }
            }
        }
    }
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

    var env_inst = rubr.Env.Instance{};
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
