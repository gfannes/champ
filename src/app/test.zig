const std = @import("std");

const rubr = @import("rubr");
const Log = rubr.log.Log;
const lsp = rubr.lsp;
const strings = rubr.strings;
const Strange = rubr.strange.Strange;
const naft = rubr.naft;
const Env = rubr.Env;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");

pub const Test = struct {
    const Self = @This();

    env: Env,
    config: *const cfg.file.Config,
    cli_args: *const cfg.cli.Args,

    forest: mero.Forest = undefined,

    pub fn init(self: *Self) !void {
        self.forest = .{ .env = self.env };
        self.forest.init();
    }
    pub fn deinit(self: *Self) void {
        self.forest.deinit();
    }

    pub fn call(self: *Self) !void {
        try self.forest.load(self.config, self.cli_args);

        var root = naft.Node{ .w = self.env.log.writer() };
        defer root.deinit();

        self.forest.chores.write(&root);
    }
};
