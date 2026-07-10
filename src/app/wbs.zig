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

    for (self.forest.chores.list.items) |chore| {
        if (chore.meta.wbs) |wbs| {
            wbs.write(&root);
        }
    }
}
