const std = @import("std");
const ut = std.testing;

pub const Config = struct {
    const Groves = std.ArrayList(Grove);

    groves: Groves,
    max_memsize: ?usize = null,

    ma: std.mem.Allocator,

    pub fn init(ma: std.mem.Allocator) Config {
        return Config{ .groves = Groves.init(ma), .ma = ma };
    }
    pub fn deinit(self: *Config) void {
        for (self.groves.items) |*grove| {
            grove.deinit();
        }
        self.groves.deinit();
    }

    pub fn loadTestDefaults(self: *Config) !void {
        self.max_memsize = 10 * 1024 * 1024 * 1024;

        var envmap = try std.process.getEnvMap(self.ma);
        defer envmap.deinit();

        var home_dir: []const u8 = "/home/geertf";
        if (envmap.get("HOME")) |dir| {
            home_dir = dir;
        }

        var buffer: [std.fs.max_path_bytes]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);
        const am_dir = try std.mem.concat(fba.allocator(), u8, &[_][]const u8{ home_dir, "/auro/root-all" });

        {
            var grove = try Grove.init("am", am_dir, self.ma);
            for ([_][]const u8{ "md", "txt", "rb", "hpp", "cpp", "h", "c", "chai" }) |ext| {
                try grove.addInclude(ext);
            }
            grove.max_size = 256000;
            try self.groves.append(grove);
        }
        {
            var grove = try Grove.init("amdebug", am_dir, self.ma);
            for ([_][]const u8{ "md", "txt", "rb", "hpp", "cpp", "h", "c", "chai" }) |ext| {
                try grove.addInclude(ext);
            }
            grove.max_count = 1;
            try self.groves.append(grove);
        }
        {
            const grove = try Grove.init("amall", am_dir, self.ma);
            try self.groves.append(grove);
        }
    }

    pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("[Config]{{\n", .{});
        for (self.groves.items) |grove| {
            try writer.print("{any}", .{grove});
        }
        try writer.print("}}\n", .{});
    }
};

test "config.Config" {
    var config = Config.init(ut.allocator);
    defer config.deinit();

    try config.loadTestDefaults();
    std.debug.print("{any}\n", .{config});
}

pub const Grove = struct {
    const Strings = std.ArrayList([]const u8);

    name: []const u8,
    path: []const u8,
    include: ?Strings = null,
    max_size: ?usize = null,
    max_count: ?usize = null,

    ma: std.mem.Allocator,

    pub fn init(name: []const u8, path: []const u8, ma: std.mem.Allocator) !Grove {
        return Grove{ .name = try ma.dupe(u8, name), .path = try ma.dupe(u8, path), .ma = ma };
    }
    pub fn deinit(self: *Grove) void {
        self.ma.free(self.name);
        self.ma.free(self.path);
        if (self.include) |include| {
            for (include.items) |el| {
                include.allocator.free(el);
            }
            include.deinit();
        }
    }

    pub fn addInclude(self: *Grove, ext: []const u8) !void {
        if (self.include == null)
            self.include = Strings.init(self.ma);

        if (self.include) |*include| {
            var buffer: [128]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(&buffer);
            const ext_with_dot = if (ext.len == 0 or ext[0] == '.') ext else try std.mem.concat(fba.allocator(), u8, &[_][]const u8{ ".", ext });
            try include.append(try self.ma.dupe(u8, ext_with_dot));
        }
    }

    pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("[Grove](name:{s})(path:{s})", .{ self.name, self.path });
        if (self.include) |include| {
            for (include.items) |ext| {
                try writer.print("(ext:{s})", .{ext});
            }
        }
        try writer.print("\n", .{});
    }
};
