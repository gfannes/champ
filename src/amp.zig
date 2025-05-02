const std = @import("std");

const Strange = @import("rubr").strange.Strange;

pub const Path = struct {
    const Self = @This();
    const Parts = std.ArrayList(Part);

    is_definition: bool = false,
    is_absolute: bool = false,
    parts: Parts,

    pub fn init(a: std.mem.Allocator) Path {
        return Path{ .parts = Parts.init(a) };
    }
    pub fn deinit(self: *Self) void {
        self.parts.deinit();
    }

    // Assumes strange outlives Path
    pub fn parse(strange: *Strange, a: std.mem.Allocator) !?Path {
        if (!strange.popChar('&'))
            return null;

        var path = Path.init(a);
        errdefer path.deinit();

        path.is_definition = strange.popChar('!');
        path.is_absolute = strange.popChar(':');

        while (strange.popTo(':')) |p|
            if (p.len > 0) {
                var s = Strange{ .content = p };
                try path.parts.append(Part.init(&s));
            };

        if (strange.popAll()) |p|
            if (p.len > 0) {
                var s = Strange{ .content = p };
                try path.parts.append(Part.init(&s));
            };

        return path;
    }

    pub fn prepend(self: *Self, prefix: Self) !void {
        self.is_definition = prefix.is_definition;
        self.is_absolute = prefix.is_absolute;
        // Assumes Part is POD
        try self.parts.insertSlice(0, prefix.parts.items);
    }

    pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("&", .{});
        if (self.is_definition)
            try writer.print("!", .{});
        var prefix: []const u8 = if (self.is_absolute) ":" else "";
        for (self.parts.items) |part| {
            const exclusive_str = if (part.is_exclusive) "!" else "";
            try writer.print("{s}{s}{s}", .{ prefix, part.content, exclusive_str });
            prefix = ":";
        }
    }
};

// Part is assumed to be POD
pub const Part = struct {
    content: []const u8,
    is_exclusive: bool = false,

    pub fn init(strange: *Strange) Part {
        const is_exclusive = strange.popCharBack('!');
        return Part{ .content = strange.str(), .is_exclusive = is_exclusive };
    }
};

test "amp" {
    const ut = std.testing;

    const Scn = struct {
        repr: []const u8,
        exp: []const u8,
    };

    const scns = [_]Scn{
        .{ .repr = "&abc", .exp = "&abc" },
        .{ .repr = "&!abc", .exp = "&!abc" },
        .{ .repr = "&:abc", .exp = "&:abc" },
        .{ .repr = "&!:abc", .exp = "&!:abc" },
        .{ .repr = "&!:abc!", .exp = "&!:abc!" },
        .{ .repr = "&!:abc!:", .exp = "&!:abc!" },
        .{ .repr = "&!:a:b!:c", .exp = "&!:a:b!:c" },
        .{ .repr = "&!:a:b!:c:", .exp = "&!:a:b!:c" },
    };

    for (scns) |scn| {
        var strange = Strange{ .content = scn.repr };
        var maybe_path = try Path.parse(&strange, ut.allocator);
        if (maybe_path) |*path| {
            defer path.deinit();
            const act = try std.fmt.allocPrint(ut.allocator, "{s}", .{path});
            try ut.expectEqualSlices(u8, scn.exp, act);
            defer ut.allocator.free(act);
        } else unreachable;
    }
}
