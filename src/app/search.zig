const std = @import("std");

const rubr = @import("rubr");
const Log = rubr.log.Log;
const lsp = rubr.lsp;
const strings = rubr.strings;

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

        try self.forest.load(self.config, self.options);

        const Ref = struct {
            ix: usize,
            score: f64,
        };
        const Refs = std.ArrayList(Ref);

        var refs = Refs.init(self.a);
        defer refs.deinit();

        var max = struct {
            name: usize = 0,
            path: usize = 0,
        }{};
        for (self.forest.chores.list.items, 0..) |chore, ix| {
            var skip_count: usize = undefined;
            const score = rubr.fuzz.distance(query, chore.str, &skip_count);
            if (skip_count > 0)
                continue;

            try refs.append(Ref{ .ix = ix, .score = score });
            max.name = @max(max.name, chore.str.len);
            max.path = @max(max.path, chore.path.len);
        }

        const Fn = struct {
            fn call(_: void, a: Ref, b: Ref) bool {
                return a.score > b.score;
            }
        };
        std.sort.block(
            Ref,
            refs.items,
            {},
            Fn.call,
        );

        const blank = try self.a.alloc(u8, @max(max.name, max.path));
        defer self.a.free(blank);
        for (blank) |*ch| ch.* = ' ';

        for (refs.items) |ref| {
            const chore = self.forest.chores.list.items[ref.ix];
            std.debug.print("{s}{s}    {s}{s}\n", .{ chore.str, blank[0 .. max.name - chore.str.len], chore.path, blank[0 .. max.path - chore.path.len] });
        }
    }
};
