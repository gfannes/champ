const std = @import("std");

pub const Grove = struct {
    name: []const u8,
    path: []const u8,
    include: [][]const u8,
    max_size: ?usize = null,
};

test "cfg_" {
    const ut = std.testing;

    var aa_ = std.heap.ArenaAllocator.init(ut.allocator);
    defer aa_.deinit();
    const aa = aa_.allocator();

    const str =
        \\.{
        \\  .{
        \\    .name = "am",
        \\    .path = "/home/geertf/am",
        \\    .include = .{"md", "rb", "hpp", "cpp", "h", "c"},
        \\    .max_size = 256000,
        \\  },
        \\  .{
        \\    .name = "gat",
        \\    .path = "/home/geertf/gatenkaas",
        \\    .include = .{"md"},
        \\  },
        \\}
    ;

    const act_groves = try std.zon.parse.fromSlice([]Grove, aa, str, null, .{});

    var include_am = [_][]const u8{ "md", "rb", "hpp", "cpp", "h", "c" };
    var include_gat = [_][]const u8{"md"};
    const exp_groves: []const Grove = &[_]Grove{ .{ .name = "am", .path = "/home/geertf/am", .include = &include_am, .max_size = 256000 }, .{
        .name = "gat",
        .path = "/home/geertf/gatenkaas",
        .include = &include_gat,
    } };

    try ut.expectEqual(exp_groves.len, act_groves.len);
    for (exp_groves, act_groves) |exp, act| {
        try ut.expectEqualSlices(u8, exp.name, act.name);
        try ut.expectEqualSlices(u8, exp.path, act.path);
        try ut.expectEqual(exp.include.len, act.include.len);
        for (exp.include, act.include) |exp_include, act_include|
            try ut.expectEqualSlices(u8, exp_include, act_include);
        try ut.expectEqual(exp.max_size, act.max_size);
    }
}
