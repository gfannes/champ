const std = @import("std");

const rubr = @import("../rubr.zig");
const lsp = rubr.lsp;
const strings = rubr.strings;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");
const qry = @import("../qry.zig");

const Self = @This();

const Entry = struct {
    filepath: []const u8,
    content: []const u8,
    rows: rubr.idx.Range,
    cols: rubr.idx.Range,
};
const Segment = struct {
    filepath: []const u8,
    entries: []const Entry,
};
const Details = struct {
    mem: bool = false,
    mero_tree: bool = false,
    amp_tree: bool = false,
    defs: bool = false,
    fn setAll(self: *@This(), b: bool) void {
        self.mero_tree = b;
        self.defs = b;
        self.amp_tree = b;
    }
};

env: rubr.Env,
config: *const cfg.file.Config,
forest: *mero.Forest,

segments: std.ArrayList(Segment) = .empty,
all_entries: std.ArrayList(Entry) = .empty,
details: Details = .{},

pub fn deinit(self: *Self) void {
    self.segments.deinit(self.env.a);
    self.all_entries.deinit(self.env.a);
}

pub fn call(self: *Self, what: [][]const u8, details: u8) !void {
    if (details > 0)
        self.details.setAll(true);
    for (what) |str| {
        if (std.mem.eql(u8, str, "mem"))
            self.details.mem = true;
        if (std.mem.eql(u8, str, "mero"))
            self.details.mero_tree = true;
        if (std.mem.eql(u8, str, "amp"))
            self.details.amp_tree = true;
        if (std.mem.eql(u8, str, "defs"))
            self.details.defs = true;
    }
}

pub fn show(self: *Self) !void {
    var root = rubr.naft.Node.root(self.env.stdout);
    defer root.deinit();

    {
        self.config.write(&root);
    }

    if (self.details.mem) {
        var n = root.node("Memory");
        defer n.deinit();

        {
            var nn = n.node("Mero");
            defer nn.deinit();

            var count: usize = 0;
            var fs_read: usize = 0;
            var terms: usize = 0;
            var filepath: usize = 0;
            var other: usize = 0;

            for (self.forest.mero_tree.nodes.items) |entry| {
                const node = entry.data;
                count += 1;
                other += @sizeOf(mero.Node);
                switch (node.type) {
                    .file => |file| {
                        fs_read += entry.data.content.len;
                        terms += file.terms.items.len * @sizeOf(mero.Term);
                        filepath += entry.data.filepath.len;
                    },
                    else => {},
                }
            }
            nn.attr("count", count);
            nn.attr("fs_read", fs_read);
            nn.attr("terms", terms);
            nn.attr("filepath", filepath);
            nn.attr("other", other);
            nn.attr("Node", @sizeOf(mero.Node));
        }

        {
            var nn = n.node("Amp");
            defer nn.deinit();

            var count: usize = 0;
            var other: usize = 0;

            for (self.forest.amp_tree.tree.nodes.items) |entry| {
                const node = entry.data;
                count += 1;
                other += @sizeOf(amp.Node);
                other += node.locations.items.len * @sizeOf(amp.Node.Location);
                other += node.ancestors.items.len * @sizeOf(usize);
            }
            nn.attr("count", count);
            nn.attr("other", other);
            nn.attr("Node", @sizeOf(amp.Node));
        }
    }

    {
        var n = root.node("mero.Tree");
        defer n.deinit();

        if (self.details.mero_tree) {
            const Cb = struct {
                env: rubr.Env,
                n: *rubr.naft.Node,

                pub fn call(my: @This(), entry: mero.Tree.Entry, before: bool) !void {
                    if (!before)
                        return;
                    entry.data.write(my.n, entry.id);
                }
            };
            const cb = Cb{ .env = self.env, .n = &n };
            try self.forest.mero_tree.dfsAll(&cb);
        } else {
            const Cb = struct {
                env: rubr.Env,
                node_count: u64 = 0,
                term_count: u64 = 0,

                pub fn call(my: *@This(), entry: mero.Tree.Entry, before: bool) !void {
                    if (!before)
                        return;
                    my.node_count += 1;
                    switch (entry.data.type) {
                        .file => |file| my.term_count += file.terms.items.len,
                        else => {},
                    }
                }
            };
            var cb = Cb{ .env = self.env };
            try self.forest.mero_tree.dfsAll(&cb);
            n.attr("node_count", cb.node_count);
            n.attr("term_count", cb.term_count);
        }
    }

    if (self.details.amp_tree) {
        self.forest.amp_tree.write(&root);
    } else {
        var n = root.node("amp.Tree");
        defer n.deinit();
        n.attr("node_count", self.forest.amp_tree.tree.nodes.items.len);
    }
}
