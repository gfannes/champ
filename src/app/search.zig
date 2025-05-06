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
        try self.forest.load(self.config, self.options);

        const Amp = struct {
            name: []const u8,
            path: []const u8,
        };

        var cb = struct {
            const My = @This();
            const Amps = std.ArrayList(Amp);
            const Max = struct {
                name: usize = 0,
                path: usize = 0,
            };

            amps: Amps,
            max: Max = .{},

            pub fn init(a: std.mem.Allocator) My {
                return My{ .amps = Amps.init(a) };
            }
            pub fn deinit(my: *My) void {
                my.amps.deinit();
            }

            pub fn call(my: *My, entry: mero.Tree.Entry) !void {
                const n = entry.data;
                if (n.def) |d| {
                    std.debug.print("def: '{}'\n", .{d});
                }
                if (n.type == mero.Node.Type.File) {
                    for (n.terms.items) |term| {
                        if (term.kind == mero.Term.Kind.Amp) {
                            try my.amps.append(Amp{ .name = term.word, .path = n.path });

                            my.max.name = @max(my.max.name, term.word.len);
                            my.max.path = @max(my.max.path, n.path.len);
                        }
                    }
                }
            }
        }.init(self.a);
        defer cb.deinit();

        try self.forest.tree.dfsAll(true, &cb);

        if (self.options.extra.items.len == 0)
            return Error.ExpectedQueryArgument;

        const query = try std.mem.concat(self.a, u8, self.options.extra.items);
        defer self.a.free(query);

        const Fn = struct {
            fn call(q: []const u8, a: Amp, b: Amp) bool {
                const dist_a = fuzz.distance(q, a.name);
                const dist_b = fuzz.distance(q, b.name);
                return dist_a > dist_b;
            }
        };
        std.sort.block(
            Amp,
            cb.amps.items,
            query,
            Fn.call,
        );

        const blank = try self.a.alloc(u8, @max(cb.max.name, cb.max.path));
        defer self.a.free(blank);
        for (blank) |*ch| ch.* = ' ';

        for (cb.amps.items) |amp| {
            std.debug.print("{s}{s}    {s}{s}\n", .{ amp.name, blank[0 .. cb.max.name - amp.name.len], amp.path, blank[0 .. cb.max.path - amp.path.len] });
        }
    }
};
