const std = @import("std");

// Loads Config from a file in ZON format
pub const Loader = struct {
    const Self = @This();

    config: ?Config = null,

    aa: std.heap.ArenaAllocator,

    // We hold an std.heap.ArenaAllocator: do not move me once an ArenaAllocator.allocator() is created/used
    pub fn init(a: std.mem.Allocator) !Self {
        return Self{ .aa = std.heap.ArenaAllocator.init(a) };
    }
    pub fn deinit(self: *Self) void {
        self.aa.deinit();
    }

    // For some reason, std.zon.parse.fromSlice() expects a sentinel string
    pub fn loadFromContent(self: *Self, content: [:0]const u8) !void {
        self.config = try std.zon.parse.fromSlice(Config, self.aa.allocator(), content, null, .{});

        try self.normalize();
    }

    pub fn loadFromFile(self: *Self, filename: []const u8) !void {
        var file = try std.fs.openFileAbsolute(filename, .{});
        defer file.close();

        // For some reason, std.zon.parse.fromSlice() expects a sentinel string
        const content = try file.readToEndAllocOptions(self.aa.allocator(), std.math.maxInt(usize), null, 1, 0);

        try self.loadFromContent(content);
    }

    // - Rework include extensions from 'md' to '.md'
    fn normalize(self: *Self) !void {
        const a = self.aa.allocator();
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

pub const Config = struct {
    groves: []Grove = &.{},
    max_memsize: ?usize = null,
    default: ?[][]const u8 = null,
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

    var loader = try Loader.init(ut.allocator);
    defer loader.deinit();

    try loader.loadFromContent(content);

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
