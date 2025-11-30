const std = @import("std");
const rubr = @import("rubr");

const Self = @This();

pub const EndOf = enum(u8) {
    Hour,
    Day,
    Week,
    Month,
    Quarter,
    Year,
};

endof: EndOf,

index: u24,

pub const Options = struct {
    pub const Index = enum { Default, Inf };
    index: Index = .Default,
};

pub fn parse(str: []const u8, options: Options) ?Self {
    var strange = rubr.strng.Strange{ .content = str };

    const ch = strange.popOne() orelse return null;
    const category: EndOf = switch (ch) {
        'a' => .Hour,
        'b' => .Day,
        'c' => .Week,
        'd' => .Month,
        'e' => .Quarter,
        'f' => .Year,
        else => return null,
    };

    const default_index: u24 = switch (options.index) {
        .Default => 5,
        .Inf => std.math.maxInt(u24),
    };
    const index: u24 = if (strange.popInt(u24)) |v| v else default_index;

    if (!strange.empty())
        return null;

    return .{ .endof = category, .index = index };
}

pub fn isLess(maybe_a: ?Self, maybe_b: ?Self) bool {
    if (maybe_a) |a| {
        if (maybe_b) |b| {
            const endof_a = @intFromEnum(a.endof);
            const endof_b = @intFromEnum(b.endof);
            if (endof_a != endof_b)
                return endof_a < endof_b;
            return a.index < b.index;
        } else {
            return true;
        }
    }
    return false;
}

test "amp.Prio" {
    const ut = std.testing;

    const Scn = struct {
        str: []const u8,
        exp: ?Self,
    };

    const scns = [_]Scn{
        .{ .str = "a", .exp = Self{ .endof = .Hour, .index = 5 } },
        .{ .str = "b", .exp = Self{ .endof = .Day, .index = 5 } },
        .{ .str = "c", .exp = Self{ .endof = .Week, .index = 5 } },
        .{ .str = "d", .exp = Self{ .endof = .Month, .index = 5 } },
        .{ .str = "e", .exp = Self{ .endof = .Quarter, .index = 5 } },
        .{ .str = "f", .exp = Self{ .endof = .Year, .index = 5 } },
        .{ .str = "h", .exp = null },
        .{ .str = "a0", .exp = Self{ .endof = .Hour, .index = 0 } },
        .{ .str = "a99", .exp = Self{ .endof = .Hour, .index = 99 } },
    };

    for (scns) |scn| {
        std.debug.print("[Scn](str:{s})\n", .{scn.str});
        if (parse(scn.str)) |act| {
            try ut.expect(scn.exp != null);
            const exp = scn.exp.?;
            try ut.expect(act.endof == exp.endof);
            try ut.expect(act.index == exp.index);
        } else {
            try ut.expect(scn.exp == null);
        }
    }
}
