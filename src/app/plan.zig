const std = @import("std");

const rubr = @import("rubr");
const Env = rubr.Env;
const lsp = rubr.lsp;
const strings = rubr.strings;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const qry = @import("../qry.zig");
const datex = @import("../datex.zig");

pub const Plan = struct {
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
        const today = try rubr.datex.Date.today();

        try self.forest.load(self.config, self.cli_args);

        var path: []const u8 = &.{};
        for (self.forest.chores.list.items, 0..) |chore, ix| {
            _ = ix;

            // Check that this is a todo, wip or next chore
            const status_value = chore.value("status", .Org) orelse continue;
            const status = status_value.status orelse continue;
            switch (status) {
                .Todo, .Wip, .Next => {},
                else => continue,
            }

            // Check that its start date is before today
            const start_value = chore.value("s", .Any) orelse continue;
            const start_date = start_value.date orelse continue;
            if (start_date.epoch_day.day > today.epoch_day.day)
                continue;

            // Skip files
            const n = try self.forest.tree.get(chore.node_id);
            if (n.type == .File)
                continue;

            if (!std.mem.eql(u8, path, n.path)) {
                path = n.path;
                try self.env.stdout.print("## {s}\n", .{path});
            }
            try self.env.stdout.print("    {s}\n", .{n.content});
        }
    }
};
