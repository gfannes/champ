const std = @import("std");

const Log = @import("rubr").log.Log;
const lsp = @import("rubr").lsp;
const strings = @import("rubr").strings;
const Strange = @import("rubr").strange.Strange;

const cfg = @import("../cfg.zig");
const cli = @import("../cli.zig");
const mero = @import("../mero.zig");

pub const Test = struct {
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
        for (self.config.groves) |cfg_grove| {
            if (!strings.contains(u8, self.options.groves.items, cfg_grove.name))
                // Skip this grove
                continue;
            try self.forest.loadGrove(&cfg_grove);
        }

        const p: []const u8 = if (self.options.extra.items.len > 0) self.options.extra.items[0] else "";
        var pattern = Strange{ .content = p };
        const only_def = pattern.popChar('!');

        if (true) {
            for (self.forest.groves.items) |grove| {
                std.debug.print("{?s}\n", .{grove.name});
                for (grove.files.items) |*file| {
                    const cb = struct {
                        const My = @This();

                        only_def: bool,

                        pub fn call(my: My, child: *mero.Node, _: ?*mero.Node) !void {
                            if (!my.only_def)
                                for (child.orgs.items) |org|
                                    std.debug.print("\torg {s}\n", .{org});
                            for (child.defs.items) |def|
                                std.debug.print("\tdef {s}\n", .{def});
                        }
                    }{ .only_def = only_def };
                    try file.root.dfsNode(null, true, cb);
                }
            }
        }

        if (false) {
            var iter = self.forest.iter();
            while (iter.next()) |e| {
                std.debug.print("{s} {s}\n", .{ e.name, e.path });
            }
        }
    }
};
