const std = @import("std");

const rubr = @import("rubr");
const Env = rubr.Env;
const lsp = rubr.lsp;
const strings = rubr.strings;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const qry = @import("../qry.zig");
const Prio = @import("../amp/Prio.zig");
const Date = @import("../amp/Date.zig");

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
        const prio_threshold = if (self.cli_args.prio) |prio_str|
            Prio.parse(prio_str, .{ .index = .Inf })
        else
            null;

        try self.forest.load(self.config, self.cli_args);

        const Entry = struct {
            path: []const u8,
            content: []const u8,
            amps: []const u8,
            prio: ?Prio,
        };
        var all_entries: std.ArrayList(Entry) = .{};
        defer all_entries.deinit(self.env.a);

        // Collect all chores
        for (self.forest.chores.list.items, 0..) |chore, ix| {
            _ = ix;

            // Check that this is a todo, wip or next chore
            const status_value = chore.value("status", .Org) orelse continue;
            const status = status_value.status orelse continue;
            switch (status.kind) {
                .Todo, .Wip, .Next => {},
                else => continue,
            }

            // Check that its start date is before today
            const start_value = chore.value("s", .Any) orelse continue;
            const start_date = start_value.date orelse continue;
            if (start_date.date.epoch_day.day > today.epoch_day.day)
                continue;

            const myprio: ?Prio = if (chore.value("p", .Any)) |value|
                value.prio
            else
                null;

            if (Prio.isLess(prio_threshold, myprio))
                continue;

            // Skip files
            const n = try self.forest.tree.get(chore.node_id);
            if (n.type == .File)
                continue;

            try all_entries.append(self.env.a, .{ .path = n.path, .content = n.content, .amps = chore.str, .prio = myprio });
        }

        // Sort according to prio, if any
        const Ctx = struct {
            pub fn call(ctx: @This(), a: Entry, b: Entry) bool {
                _ = ctx;
                return Prio.isLess(a.prio, b.prio);
            }
        };
        std.sort.block(Entry, all_entries.items, Ctx{}, Ctx.call);

        const Segment = struct {
            path: []const u8,
            entries: []const Entry,
        };
        var segments: std.ArrayList(Segment) = .{};
        defer segments.deinit(self.env.a);
        for (all_entries.items, 0..) |entry, ix0| {
            const prev_path = if (segments.items.len == 0) "" else segments.items[segments.items.len - 1].path;
            if (!std.mem.eql(u8, prev_path, entry.path)) {
                try segments.append(self.env.a, Segment{ .path = entry.path, .entries = all_entries.items[ix0 .. ix0 + 1] });
            } else {
                segments.items[segments.items.len - 1].entries.len += 1;
            }
        }

        if (!self.cli_args.reverse)
            std.mem.reverse(Segment, segments.items);

        // Showtime
        for (segments.items) |segment| {
            try self.env.stdout.print("## {s}\n", .{segment.path});
            for (segment.entries) |entry| {
                try self.env.stdout.print("    {s}", .{entry.content});
                if (self.cli_args.details)
                    try self.env.stdout.print(" ({s})", .{entry.amps});
                try self.env.stdout.print("\n", .{});
            }
        }
    }
};
