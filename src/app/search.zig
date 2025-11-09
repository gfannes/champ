const std = @import("std");

const rubr = @import("rubr");
const Env = rubr.Env;
const lsp = rubr.lsp;
const strings = rubr.strings;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const qry = @import("../qry.zig");

pub const Error = error{
    ExpectedQueryArgument,
};

pub const Search = struct {
    const Self = @This();

    env: Env,
    config: *const cfg.file.Config,
    cli_args: *const cfg.cli.Args,

    forest: mero.Forest = undefined,

    pub fn init(self: *Self) !void {
        self.forest = mero.Forest{ .env = self.env };
        self.forest.init();
    }
    pub fn deinit(self: *Self) void {
        self.forest.deinit();
    }

    pub fn call(self: *Self) !void {
        if (self.cli_args.extra.items.len == 0)
            return Error.ExpectedQueryArgument;

        var query = qry.Query.init(self.env.a);
        defer query.deinit();
        try query.setup(self.cli_args.extra.items);

        try self.forest.load(self.config, self.cli_args);

        const Ref = struct {
            ix: usize,
            score: f64,
        };
        const Refs = std.ArrayList(Ref);

        var refs = Refs{};
        defer refs.deinit(self.env.a);

        var max = struct {
            name: usize = 0,
            path: usize = 0,
        }{};
        for (self.forest.chores.list.items, 0..) |chore, ix| {
            if (query.distance(chore)) |distance| {
                try refs.append(self.env.a, Ref{ .ix = ix, .score = distance });
                max.name = @max(max.name, chore.str.len);
                max.path = @max(max.path, chore.path.len);
            }
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

        const blank = try self.env.a.alloc(u8, @max(max.name, max.path));
        defer self.env.a.free(blank);
        for (blank) |*ch| ch.* = ' ';

        for (refs.items) |ref| {
            const chore = self.forest.chores.list.items[ref.ix];
            const line = if (rubr.slc.firstPtr(chore.parts.items)) |part| part.row + 1 else 0;
            try self.env.log.print("{s}{s}    {s}{s}:{} {}\n", .{ chore.str, blank[0 .. max.name - chore.str.len], chore.path, blank[0 .. max.path - chore.path.len], line, ref.score });
        }
    }
};
