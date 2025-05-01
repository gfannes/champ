const std = @import("std");

const Log = @import("rubr").log.Log;
const lsp = @import("rubr").lsp;
const strings = @import("rubr").strings;
const fuzz = @import("rubr").fuzz;

const cfg = @import("../cfg.zig");
const cli = @import("../cli.zig");
const mero = @import("../mero.zig");

pub const Error = error{
    ExpectedQueryArgument,
};

pub const Search = struct {
    const Self = @This();

    config: *const cfg.Config,
    options: *const cli.Options,
    log: *const Log,
    a: std.mem.Allocator,

    forest: mero.Forest = undefined,

    pub fn init(self: *Self) !void {
        self.forest = mero.Forest.init(self.log, self.a);
    }
    pub fn deinit(self: *Self) void {
        self.forest.deinit();
    }

    pub fn call(self: *Self) !void {
        if (self.options.extra.items.len == 0)
            return Error.ExpectedQueryArgument;

        const query = try std.mem.concat(self.a, u8, self.options.extra.items);
        defer self.a.free(query);

        for (self.config.groves) |cfg_grove| {
            if (!strings.contains(u8, self.options.groves.items, cfg_grove.name))
                // Skip this grove
                continue;
            try self.forest.loadGrove(&cfg_grove);
        }

        // &fixme
        // const Value = mero.Forest.Iter.Value;

        // var amps = std.ArrayList(Value).init(self.a);
        // defer amps.deinit();

        // var max = struct {
        //     name: usize = 0,
        //     path: usize = 0,
        // }{};

        // var iter = self.forest.iter();
        // while (iter.next()) |e| {
        //     max.name = @max(max.name, e.name.len);
        //     max.path = @max(max.path, e.path.len);
        //     try amps.append(e);
        // }
        // std.debug.print("{any}\n", .{max});

        // const Fn = struct {
        //     fn call(q: []const u8, a: Value, b: Value) bool {
        //         const dist_a = fuzz.distance(q, a.name);
        //         const dist_b = fuzz.distance(q, b.name);
        //         return dist_a > dist_b;
        //     }
        // };
        // std.sort.block(
        //     Value,
        //     amps.items,
        //     query,
        //     Fn.call,
        // );

        // const blank = try self.a.alloc(u8, @max(max.name, max.path));
        // defer self.a.free(blank);
        // for (blank) |*ch| ch.* = ' ';

        // for (amps.items) |amp| {
        //     std.debug.print("{s}{s}    {s}{s}\n", .{ amp.name, blank[0 .. max.name - amp.name.len], amp.path, blank[0 .. max.path - amp.path.len] });
        // }
    }
};
