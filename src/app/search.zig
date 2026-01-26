const std = @import("std");

const rubr = @import("rubr");
const Env = rubr.Env;
const lsp = rubr.lsp;
const strings = rubr.strings;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const qry = @import("../qry.zig");

pub const Search = struct {
    const Self = @This();
    const Entry = struct {
        path: []const u8,
        content: []const u8,
        amps: []const u8,
        score: f64,
        rows: rubr.idx.Range,
        cols: rubr.idx.Range,
    };
    const Segment = struct {
        path: []const u8,
        entries: []const Entry,
    };
    const Max = struct {
        name: usize = 0,
        path: usize = 0,
        fn update(self: *@This(), name_len: usize, path_len: usize) void {
            self.name = @max(self.name, name_len);
            self.path = @max(self.path, path_len);
        }
        fn max(self: @This()) usize {
            return @max(self.name, self.path);
        }
    };

    env: Env,
    config: *const cfg.file.Config,
    forest: *const mero.Forest,

    segments: std.ArrayList(Segment) = .{},
    all_entries: std.ArrayList(Entry) = .{},
    max: Max = .{},

    pub fn deinit(self: *Self) void {
        self.segments.deinit(self.env.a);
        self.all_entries.deinit(self.env.a);
    }

    pub fn call(self: *Self, query_input: [][]const u8, reverse: bool) !void {
        var query = qry.Query{ .a = self.env.a };
        defer query.deinit();
        try query.setup(query_input);

        for (self.forest.chores.list.items) |chore| {
            if (query.distance(chore)) |distance| {
                const n = try self.forest.tree.cget(chore.node_id);
                if (n.type == .file)
                    continue;
                try self.all_entries.append(
                    self.env.a,
                    Entry{
                        .path = n.path,
                        .content = n.content,
                        .amps = chore.str,
                        .score = distance,
                        .rows = n.content_rows,
                        .cols = n.content_cols,
                    },
                );
                self.max.update(chore.str.len, chore.path.len);
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
        const blank = try self.env.a.alloc(u8, self.max.max());
        defer self.env.a.free(blank);
        for (blank) |*ch| ch.* = ' ';

        for (self.segments.items) |segment| {
            try self.env.stdout.print("\n{s}\n", .{segment.path});
            for (segment.entries) |entry| {
                try self.env.stdout.print("  {s}", .{entry.content});
                if (details)
                    try self.env.stdout.print(" ({}, {s})", .{ entry.score, entry.amps });
                try self.env.stdout.print("\n", .{});
            }
        }
    }
};
