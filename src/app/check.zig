const std = @import("std");

const rubr = @import("rubr");
const Env = rubr.Env;
const lsp = rubr.lsp;
const strings = rubr.strings;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const qry = @import("../qry.zig");

pub const Check = struct {
    const Self = @This();
    const Entry = struct {
        path: []const u8,
        content: []const u8,
        rows: rubr.idx.Range,
        cols: rubr.idx.Range,
    };
    const Segment = struct {
        path: []const u8,
        entries: []const Entry,
    };

    env: Env,
    cli_args: *const cfg.cli.Args,
    forest: *mero.Forest,

    segments: std.ArrayList(Segment) = .{},
    all_entries: std.ArrayList(Entry) = .{},

    pub fn deinit(self: *Self) void {
        self.segments.deinit(self.env.a);
        self.all_entries.deinit(self.env.a);
    }

    pub fn call(self: *Self) !void {
        _ = self;
    }

    pub fn show(self: *Self, details: u8) !void {
        var root = rubr.naft.Node.root(self.env.stdout);
        defer root.deinit();

        {
            var n = root.node("Tree");
            defer n.deinit();

            if (details == 0) {
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
                try self.forest.tree.dfsAll(&cb);
                n.attr("node_count", cb.node_count);
                n.attr("term_count", cb.term_count);
            } else {
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
                try self.forest.tree.dfsAll(&cb);
            }
        }

        {
            var n = root.node("DefMgr");
            defer n.deinit();
            if (details == 0) {
                n.attr("count", self.forest.defmgr.defs.items.len);
            } else {
                for (self.forest.defmgr.defs.items, 0..) |def, ix| {
                    var nn = n.node("Def");
                    defer nn.deinit();
                    nn.attr("ix", ix);
                    nn.attr("ap", def.ap);
                }
            }
        }

        if (details == 0) {
            var n = root.node("Chores");
            defer n.deinit();
            n.attr("count", self.forest.chores.list.items.len);
        } else {
            self.forest.chores.write(&root);
        }
    }
};
