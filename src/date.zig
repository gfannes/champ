const std = @import("std");
const rubr = @import("rubr");

pub fn parse(str: []const u8, strict_end: bool) ?rubr.date.Date {
    var strange = rubr.strng.Strange{ .content = str };

    // YEAR
    var year: u16 = 0;
    if (strange.popChar('y')) {
        year = strange.popInt(u16) orelse return null;
        if (year < 100)
            year += 2000;
    } else if (strange.popFront(4)) |yyyy| {
        year = std.fmt.parseInt(u16, yyyy, 10) catch return null;
    } else {
        // We expect a year to be given
        return null;
    }
    if (year < 1970)
        return null;

    _ = strange.popChar('-');
    _ = strange.popChar('/');

    var days: u47 = 0;

    if (strange.popChar('w')) {
        // WEEK

        // Process the full years, keeping track at what offset w1 starts
        // 1970/1/1 was a Thursday: offset 3 when starting from Monday
        var offset_w1: u32 = 3;
        for (1970..year) |y| {
            const days_in_year = std.time.epoch.getDaysInYear(@intCast(y));
            days += days_in_year;
            offset_w1 = (offset_w1 + days_in_year) % 7;
        }

        const week = strange.popInt(u32) orelse return null;
        if (week == 0 or week > 53) {
            return null;
        } else if (week > 1) {
            days += (7 - offset_w1) + 7 * (week - 2);
        }
    } else {
        for (1970..year) |y|
            days += std.time.epoch.getDaysInYear(@intCast(y));

        if (strange.popChar('q')) {
            // QUARTER
            const q = strange.popInt(u3) orelse return null;

            const leap: u47 = if (std.time.epoch.isLeapYear(year)) 1 else 0;
            switch (q) {
                1 => days += 0,
                2 => days += 31 + 28 + leap + 31,
                3 => days += 31 + 28 + leap + 31 + 30 + 31 + 30,
                4 => days += 31 + 28 + leap + 31 + 30 + 31 + 30 + 31 + 31 + 30,
                else => return null,
            }
        } else {
            if (strange.popIntMaxCount(u16, 2)) |month| {
                if (month < 1 or month > 12)
                    return null;
                for (1..month) |m|
                    days += std.time.epoch.getDaysInMonth(@intCast(year), @enumFromInt(m));

                _ = strange.popChar('-');
                _ = strange.popChar('/');

                if (strange.popIntMaxCount(u16, 2)) |day| {
                    if (day < 1)
                        return null;
                    days += (day - 1);
                }
            }
        }
    }

    if (strict_end and !strange.empty())
        return null;

    return rubr.date.Date.fromEpochDays(days);
}

test "date" {
    const ut = std.testing;

    const Scn = struct {
        str: []const u8,
        exp: ?[]const u8,
        strict_end: bool = true,
    };

    const scns = [_]Scn{
        .{ .str = "y2025", .exp = "20250101" },
        .{ .str = "y25", .exp = "20250101" },
        .{ .str = "q1", .exp = null },
        .{ .str = "q2", .exp = null },
        .{ .str = "q3", .exp = null },
        .{ .str = "q4", .exp = null },
        .{ .str = "y25q1", .exp = "20250101" },
        .{ .str = "y25q2", .exp = "20250401" },
        .{ .str = "y25q3", .exp = "20250701" },
        .{ .str = "y25q4", .exp = "20251001" },
        .{ .str = "y26q2", .exp = "20260401" },
        .{ .str = "w1", .exp = null },
        .{ .str = "w2", .exp = null },
        .{ .str = "y25w1", .exp = "20250101" },
        .{ .str = "y25w2", .exp = "20250106" },
        .{ .str = "y25w52", .exp = "20251222" },
        .{ .str = "y26w2", .exp = "20260105" },
        .{ .str = "19780105", .exp = "19780105" },
        .{ .str = "2025", .exp = "20250101" },
        .{ .str = "202502", .exp = "20250201" },
        .{ .str = "1231", .exp = null },
        .{ .str = "2025-01-02", .exp = "20250102" },
        .{ .str = "2025-1-2", .exp = "20250102" },
        .{ .str = "2025-2", .exp = "20250201" },
        .{ .str = "2025-2 ", .exp = "20250201", .strict_end = false },
        .{ .str = "2025-01-02rest", .exp = "20250102", .strict_end = false },
    };

    for (&scns) |scn| {
        std.debug.print("[Scn](str:{s})(exp:{?s})\n", .{ scn.str, scn.exp });
        if (parse(scn.str, scn.strict_end)) |date| {
            var aw = std.Io.Writer.Allocating.init(ut.allocator);
            try aw.writer.print("{f}", .{date});
            const act = try aw.toOwnedSlice();
            defer ut.allocator.free(act);

            try ut.expect(scn.exp != null);
            try ut.expectEqualStrings(scn.exp.?, act);
        } else {
            try ut.expect(scn.exp == null);
        }
    }
}
