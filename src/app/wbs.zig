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
    _ = self;
}
