const std = @import("std");

const rubr = @import("../rubr.zig");

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");

const Self = @This();

env: rubr.Env,
config: *const cfg.file.Config,
forest: *const mero.Forest,

details: bool = true,

pub fn init(_: *Self) !void {}
pub fn deinit(_: *Self) void {}

pub fn call(self: *Self) !void {
    var root = rubr.naft.Node.root(self.env.stdout);
    defer root.deinit();

    for (self.forest.amp_tree.tree.nodes.items) |entry| {
        const node = entry.data;
        const meta = node.meta orelse continue;

        if (meta.wbs) |wbs| {
            wbs.write(&root);
        }
    }
}
