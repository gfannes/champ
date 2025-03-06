const std = @import("std");
const ut = std.testing;

pub const Grove = struct {
    const Strings = std.ArrayList([]const u8);

    name: []const u8,
    path: []const u8,
    include: Strings,

    ma: std.mem.Allocator,

    pub fn init(name: []const u8, path: []const u8, ma: std.mem.Allocator) !Grove {
        return Grove{ .name = try ma.dupe(u8, name), .path = try ma.dupe(u8, path), .include = Strings.init(ma), .ma = ma };
    }
    pub fn deinit(self: *Grove) void {
        self.ma.free(self.name);
        self.ma.free(self.path);
        for (self.include.items) |el| {
            self.ma.free(el);
        }
        self.include.deinit();
    }

    pub fn addInclude(self: *Grove, ext: []const u8) !void {
        try self.include.append(try self.ma.dupe(u8, ext));
    }

    pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("[Grove](name:{s})(path:{s})", .{ self.name, self.path });
        for (self.include.items) |ext| {
            try writer.print("(ext:{s})", .{ext});
        }
        try writer.print("\n", .{});
    }
};

pub const Config = struct {
    const Groves = std.ArrayList(Grove);

    groves: Groves,
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

    pub fn loadDefault(self: *Config) !void {
        var grove = try Grove.init("am", "/home/geertf/ma", self.ma);
        for ([_][]const u8{ "md", "txt", "rb", "hpp", "cpp", "h", "c", "chai" }) |ext| {
            try grove.addInclude(ext);
        }
        try self.groves.append(grove);
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

    try config.loadDefault();
    std.debug.print("{any}\n", .{config});
}
