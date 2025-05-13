const std = @import("std");

const rubr = @import("rubr");
const Log = rubr.log.Log;
const lsp = rubr.lsp;
const strings = rubr.strings;
const Strange = rubr.strange.Strange;
const naft = rubr.naft;

const cfg = @import("../cfg.zig");
const cli = @import("../cli.zig");
const mero = @import("../mero.zig");
const chore = @import("../chore.zig");

pub const Test = struct {
    const Self = @This();

    config: *const cfg.Config,
    options: *const cli.Options,
    log: *const Log,
    a: std.mem.Allocator,

    forest: mero.Forest = undefined,

    pub fn init(self: *Self) !void {
        self.forest = mero.Forest.init(self.log, self.a);
    }
    pub fn deinit(self: *Self) void {
        self.forest.deinit();
    }

    pub fn call(self: *Self) !void {
        try self.forest.load(self.config, self.options);

        var cb = struct {
            const My = @This();

            tree: *const mero.Tree,
            chores: chore.Chores,

            pub fn init(tree: *const mero.Tree, log: *const Log, a: std.mem.Allocator) My {
                return My{ .tree = tree, .chores = chore.Chores.init(log, a) };
            }
            pub fn deinit(my: *My) void {
                my.chores.deinit();
            }

            pub fn call(my: *My, entry: mero.Tree.Entry) !void {
                // std.debug.print("{:<6}{?}\t{s}\t{}{}\n", .{ entry.id, entry.data.type, entry.data.path, entry.data.content_rows, entry.data.content_cols });
                _ = try my.chores.add(entry.id, my.tree.*);
            }
        }.init(&self.forest.tree, self.log, self.a);
        defer cb.deinit();

        try self.forest.tree.dfsAll(true, &cb);

        var root = naft.Node.init(null);
        defer root.deinit();

        cb.chores.write(&root);
    }
};
