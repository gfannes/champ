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
    forest: *const mero.Forest,

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
        _ = details;

        try self.env.stdout.print("[DefMgr]\n", .{});
        for (self.forest.defmgr.defs.items, 0..) |def, ix| {
            try self.env.stdout.print("  {} {f}\n", .{ ix, def.ap });
        }

        {
            var root = rubr.naft.Node{ .w = self.env.stdout };
            self.forest.chores.write(&root);
        }
    }
};
