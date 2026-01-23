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

    pub fn show(self: Self, details: bool) !void {
        var root = rubr.naft.Node.root(self.env.stdout);
        defer root.deinit();

        if (details) {
            var n = root.node("Tree");
            defer n.deinit();

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

        {
            var n = root.node("DefMgr");
            defer n.deinit();
            for (self.forest.defmgr.defs.items, 0..) |def, ix| {
                var nn = n.node("Def");
                defer nn.deinit();
                nn.attr("ix", ix);
                nn.attr("ap", def.ap);
            }
        }

        self.forest.chores.write(&root);
    }
};
