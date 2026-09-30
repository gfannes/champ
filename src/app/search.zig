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
    amps: []const u8,
    score: f64,
    rows: rubr.idx.Range,
    cols: rubr.idx.Range,
};
const Segment = struct {
    filepath: []const u8,
    entries: []const Entry,
};
const Max = struct {
    name: usize = 0,
    filepath: usize = 0,
    fn update(self: *@This(), name_len: usize, path_len: usize) void {
        self.name = @max(self.name, name_len);
        self.filepath = @max(self.filepath, path_len);
    }
    fn max(self: @This()) usize {
        return @max(self.name, self.filepath);
    }
};

env: Env,
config: *const cfg.file.Config,
forest: *const mero.Forest,

segments: std.ArrayList(Segment) = .empty,
all_entries: std.ArrayList(Entry) = .empty,
max: Max = .{},

pub fn deinit(self: *Self) void {
    self.segments.deinit(self.env.a);
    self.all_entries.deinit(self.env.a);
}

pub fn call(self: *Self, query_input: [][]const u8, reverse: bool) !void {
    var query = qry.Query{ .a = self.env.a };
    defer query.deinit();
    try query.setup(query_input);

    for (self.forest.amp_tree.tree.nodes.items) |entry| {
        const node = entry.data;
        const meta = node.meta orelse continue;

        var aps: std.ArrayList(amp.Path) = .empty;
        defer {
            for (aps.items) |*ap|
                ap.deinit();
            aps.deinit(self.env.a);
        }

        for (node.ancestors.items) |ancestor| {
            try aps.append(self.env.a, try self.forest.amp_tree.ampPath(self.env.a, ancestor));
        }

        try query.prepare(meta, self.config.default_worker);

        for (aps.items) |*ap| {
            try query.add(ap);
        }

        if (query.distance()) |distance| {
            if (rubr.slc.first(node.locations.items)) |location| {
                const mero_node = self.forest.mero_tree.cptr(location.mero_id);
                try self.all_entries.append(
                    self.env.a,
                    .{
                        .filepath = location.path,
                        .content = mero_node.content,
                        .amps = mero_node.content,
                        .score = distance,
                        .rows = mero_node.content_rows,
                        .cols = mero_node.content_cols,
                    },
                );
                self.max.update(mero_node.content.len, location.path.len);
            }
        }
    }

    // Small score is better
    const Fn = struct {
        fn call(_: void, a: Entry, b: Entry) bool {
            return a.score < b.score;
        }
    };
    std.sort.block(Entry, self.all_entries.items, {}, Fn.call);

    for (self.all_entries.items, 0..) |entry, ix0| {
        const prev_path = if (rubr.slc.last(self.segments.items)) |item| item.filepath else "";
        if (!std.mem.eql(u8, prev_path, entry.filepath)) {
            try self.segments.append(self.env.a, Segment{ .filepath = entry.filepath, .entries = self.all_entries.items[ix0 .. ix0 + 1] });
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
    const blank = try self.env.a.alloc(u8, self.max.max());
    defer self.env.a.free(blank);
    for (blank) |*ch| ch.* = ' ';

    for (self.segments.items) |segment| {
        try self.env.stdout.print("\n{s}\n", .{segment.filepath});
        for (segment.entries) |entry| {
            try self.env.stdout.print("  {s}", .{entry.content});
            if (details)
                try self.env.stdout.print(" ({}, {s})", .{ entry.score, entry.amps });
            try self.env.stdout.print("\n", .{});
        }
    }
}
