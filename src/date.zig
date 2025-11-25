const std = @import("std");
const rubr = @import("rubr");

pub fn parse(str: []const u8) ?rubr.date.Date {
    const today = rubr.date.Date.today() catch return null;
    var yd = today.yearDay();

    var strange = rubr.strng.Strange{ .content = str };

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
    }

    var days: u47 = yd.day;
    for (1970..yd.year) |year| {
        days += std.time.epoch.getDaysInYear(@intCast(year));
    }

    return rubr.date.Date.fromEpochDays(days);
}

test "date" {
    const ut = std.testing;
    _ = ut;

    const maybe_date = parse("q4");
    if (maybe_date) |date|
        std.debug.print("date: {f}\n", .{date});
}
