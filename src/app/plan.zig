const std = @import("std");

const rubr = @import("../rubr.zig");
const Env = rubr.Env;
const lsp = rubr.lsp;
const strings = rubr.strings;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const qry = @import("../qry.zig");
const amp = @import("../amp.zig");

const Self = @This();
const Entry = struct {
    filepath: []const u8,
    content: []const u8,
    date: ?amp.Date,
    order: i32,
    rows: rubr.idx.Range,
    cols: rubr.idx.Range,
};
const Segment = struct {
    filepath: []const u8,
    order: i32,
    entries: []const Entry,
};

env: Env,
config: *const cfg.file.Config,
forest: *const mero.Forest,

segments: std.ArrayList(Segment) = .empty,
all_entries: std.ArrayList(Entry) = .empty,

pub fn deinit(self: *Self) void {
    self.segments.deinit(self.env.a);
    self.all_entries.deinit(self.env.a);
}

pub fn call(self: *Self, max_order: i32, query_input: []const []const u8, reverse: bool) !void {
    const today = try rubr.datex.Date.today(self.env.io);

    var query = qry.Query{ .a = self.env.a };
    defer query.deinit();
    try query.setup(query_input);

    // Collect all chores
    for (self.forest.chores.list.items) |chore| {
        const status = chore.meta.status orelse continue;
        switch (status.kind) {
            .Todo, .Wip, .Go, .Blocked, .Question => {},
            else => continue,
        }

        const myorder = chore.order();
        if (myorder > max_order)
            continue;

        try query.prepare(chore, self.config.default_worker);
        const node = self.forest.tree.cptr(chore.node_id);
        for (node.org_amps.items) |ref| {
            const def = ref.ix.cptr(self.forest.defmgr.defs.items);
            try query.add(&def.path);
        }
        for (node.agg_amps.items) |ref| {
            const def = ref.cptr(self.forest.defmgr.defs.items);
            try query.add(&def.path);
        }

        // Check correspondence with provided query
        const distance = query.distance() orelse continue;
        if (distance > 1.0)
            continue;

        // Check that its start date is before today, if any
        // &todo &meta Add date to chore and re-enable this check
        const date = if (chore.meta.date) |date| ret: {
            if (date.date.epoch_day.day > today.epoch_day.day)
                continue;
            break :ret date;
        } else null;

        const n = self.forest.tree.cptr(chore.node_id);

        const entry = Entry{
            .filepath = n.filepath,
            .content = n.content,
            .date = date,
            .order = myorder,
            .rows = n.content_rows,
            .cols = n.content_cols,
        };

        try self.all_entries.append(
            self.env.a,
            entry,
        );
    }

    // Sort according to:
    // - Order, if any
    // - Date: recent chores first
    const Fn = struct {
        pub fn call(ctx: @This(), a: Entry, b: Entry) bool {
            _ = ctx;
            return order(a, b) == .lt;
        }
        fn order(a: Entry, b: Entry) std.math.Order {
            const ord = std.math.order(a.order, b.order);
            if (ord != .eq)
                return ord;
            return amp.Date.order(b.date, a.date);
        }
    };
    std.sort.block(Entry, self.all_entries.items, Fn{}, Fn.call);

    for (self.all_entries.items, 0..) |entry, ix0| {
        const prev_path = if (rubr.slc.last(self.segments.items)) |item| item.filepath else "";
        if (!std.mem.eql(u8, prev_path, entry.filepath)) {
            try self.segments.append(self.env.a, Segment{ .filepath = entry.filepath, .order = entry.order, .entries = self.all_entries.items[ix0 .. ix0 + 1] });
        } else {
            if (rubr.slc.lastPtr(self.segments.items)) |ptr|
                ptr.entries.len += 1;
        }
    }

    // // &todo: Handle this in show() with an iterator that can be configured at runtime between normal/reverse
    if (reverse)
        std.mem.reverse(Segment, self.segments.items);
}

fn style(order: i32) rubr.ansi.Style {
    const colors: []const rubr.ansi.Style.Ground.Color = &.{ .Red, .Yellow, .Green, .Magenta, .Blue, .Cyan, .White };

    const color = if (order < 0)
        colors[0]
    else block: {
        const uorder: usize = @intCast(order);

        var ix: usize = uorder / 10;
        if (ix >= colors.len)
            ix = colors.len - 1;
        break :block colors[ix];
    };

    const bold = @rem(order, 10) == 0;

    return rubr.ansi.Style{ .fg = .{ .color = color }, .bold = bold };
}

pub fn show(self: Self, all: bool, details: bool) !void {
    // &todo Use `all` to show all tasks
    _ = all;
    _ = details;

    for (self.segments.items) |segment| {
        const filename_style = rubr.ansi.Style{ .fg = .{ .color = .White, .intense = true }, .underline = true };
        const reset_style = rubr.ansi.Style{ .reset = true };
        try self.env.stdout.print("\n{f}{s}{f}\n", .{ filename_style, segment.filepath, reset_style });

        for (segment.entries) |entry| {
            try self.env.stdout.print("  {f}{s}{f} (&#{})", .{ style(entry.order), entry.content, reset_style, entry.order });
            try self.env.stdout.print("\n", .{});
        }
    }
}
