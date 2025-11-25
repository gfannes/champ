const std = @import("std");
const rubr = @import("rubr");

pub fn parse(str: []const u8) ?rubr.date.Date {
    const today = rubr.date.Date.today() catch return null;
    var yd = today.yearDay();

    var strange = rubr.strng.Strange{ .content = str };

    if (strange.popChar('y')) {
        yd.year = strange.popInt(u16) orelse return null;
        if (yd.year < 100)
            yd.year += 2000;
        yd.day = 0;
    }

    var days: u47 = 0;

    if (strange.popChar('q')) {
        if (strange.popInt(u3)) |v| {
            yd.day = if (std.time.epoch.isLeapYear(yd.year)) 1 else 0;
            switch (v) {
                1 => yd.day = 0,
                2 => yd.day += 31 + 28 + 31,
                3 => yd.day += 31 + 28 + 31 + 30 + 31 + 30,
                4 => yd.day += 31 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 30,
                else => return null,
            }
        }
        if (!strange.empty())
            return null;

        days = yd.day;
        for (1970..yd.year) |year| {
            days += std.time.epoch.getDaysInYear(@intCast(year));
        }
    } else if (strange.popChar('w')) {
        // Process the full years, keeping track at what offset w1 starts
        // 1970/1/1 was a Thursday: offset 3 when starting from Monday
        var offset_w1: u32 = 3;
        for (1970..yd.year) |year| {
            const days_in_year = std.time.epoch.getDaysInYear(@intCast(year));
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
        var year: u32 = 0;
        var month: u16 = 0;
        var day: u16 = 1;

        if (strange.popInt(u32)) |ymd| {
            if (ymd <= 1231) {
                const mmdd = ymd;

                year = yd.year;
                month = @intCast(mmdd / 100);
                day = @intCast(mmdd % 100);
            } else if (ymd < 10000) {
                const yyyy = ymd;

                year = yyyy;
                month = 1;
            } else if (ymd <= 1000000) {
                const yyyymm = ymd;

                year = @intCast(yyyymm / 100);
                month = @intCast(yyyymm % 100);
            } else {
                const yyyymmdd = ymd;

                year = yyyymmdd / 10000;
                const mmdd = yyyymmdd % 10000;
                month = @intCast(mmdd / 100);
                day = @intCast(mmdd % 100);
            }
        } else {
            year = yd.year;
            month = 1;
        }

        for (1970..year) |y| {
            days += std.time.epoch.getDaysInYear(@intCast(y));
        }

        if (month < 1 or month > 12)
            return null;
        for (1..month) |m|
            days += std.time.epoch.getDaysInMonth(@intCast(year), @enumFromInt(m));

        if (day < 1)
            return null;
        days += (day - 1);
    }
    return rubr.date.Date.fromEpochDays(days);
}

test "date" {
    const Error = error{CouldNotParse};
    const ut = std.testing;

    const Scn = struct {
        str: []const u8,
        exp: []const u8,
    };

    const scns = [_]Scn{
        .{ .str = "q1", .exp = "20250101" },
        .{ .str = "q2", .exp = "20250401" },
        .{ .str = "q3", .exp = "20250701" },
        .{ .str = "q4", .exp = "20251001" },
        .{ .str = "y10", .exp = "20100101" },
        .{ .str = "y26q2", .exp = "20260401" },
        .{ .str = "w1", .exp = "20250101" },
        .{ .str = "w2", .exp = "20250106" },
        .{ .str = "w52", .exp = "20251222" },
        .{ .str = "y26w2", .exp = "20260105" },
        .{ .str = "19780105", .exp = "19780105" },
        .{ .str = "2025", .exp = "20250101" },
        .{ .str = "202502", .exp = "20250201" },
        .{ .str = "1112", .exp = "20251112" },
    };

    for (&scns) |scn| {
        const date = parse(scn.str) orelse return Error.CouldNotParse;
        std.debug.print("str: {s}, date: {f}\n", .{ scn.str, date });

        var aw = std.Io.Writer.Allocating.init(ut.allocator);
        try aw.writer.print("{f}", .{date});
        const act = try aw.toOwnedSlice();
        defer ut.allocator.free(act);

        try ut.expectEqualStrings(scn.exp, act);
    }
}
