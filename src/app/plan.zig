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
    const Entry = struct {
        path: []const u8,
        content: []const u8,
        amps: []const u8,
        prio: ?Prio,
        rows: rubr.idx.Range,
        cols: rubr.idx.Range,
    };
    const Segment = struct {
        path: []const u8,
        entries: []const Entry,
    };

    env: Env,
    cli_args: *const cfg.cli.Args,
    forest: *const mero.Forest,

    segments: std.ArrayList(Segment) = .{},
    all_entries: std.ArrayList(Entry) = .{},

    pub fn deinit(self: *Self) void {
        self.segments.deinit(self.env.a);
        self.all_entries.deinit(self.env.a);
    }

    pub fn call(self: *Self, prio_threshold: ?Prio, reverse: bool) !void {
        const today = try rubr.datex.Date.today();

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
            std.debug.print("start_date: {f}\n", .{start_date});
            if (start_date.date.epoch_day.day > today.epoch_day.day)
                continue;

            const myprio: ?Prio = if (chore.value("p", .Any)) |value|
                value.prio
            else
                null;

            if (Prio.isLess(prio_threshold, myprio))
                continue;

            // Skip files
            const n = try self.forest.tree.cget(chore.node_id);
            if (n.type == .File)
                continue;

            try self.all_entries.append(
                self.env.a,
                Entry{
                    .path = n.path,
                    .content = n.content,
                    .amps = chore.str,
                    .prio = myprio,
                    .rows = n.content_rows,
                    .cols = n.content_cols,
                },
            );
        }

        // Sort according to prio, if any
        const Fn = struct {
            pub fn call(ctx: @This(), a: Entry, b: Entry) bool {
                _ = ctx;
                return Prio.isLess(a.prio, b.prio);
            }
        };
        std.sort.block(Entry, self.all_entries.items, Fn{}, Fn.call);

        for (self.all_entries.items, 0..) |entry, ix0| {
            const prev_path = if (rubr.slc.last(self.segments.items)) |item| item.path else "";
            if (!std.mem.eql(u8, prev_path, entry.path)) {
                try self.segments.append(self.env.a, Segment{ .path = entry.path, .entries = self.all_entries.items[ix0 .. ix0 + 1] });
            } else {
                if (rubr.slc.lastPtr(self.segments.items)) |ptr|
                    ptr.entries.len += 1;
            }
        }

        // &todo: Handle this in show() with an iterator that can be configured at runtime between normal/reverse
        if (reverse)
            std.mem.reverse(Segment, self.segments.items);
    }

    pub fn show(self: Self, details: bool) !void {
        for (self.segments.items) |segment| {
            try self.env.stdout.print("\n{s}\n", .{segment.path});
            for (segment.entries) |entry| {
                try self.env.stdout.print("  {s}", .{entry.content});
                if (details)
                    try self.env.stdout.print(" ({s})", .{entry.amps});
                try self.env.stdout.print("\n", .{});
            }
        }
    }
};
