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

        var root = naft.Node.init(self.log.writer());
        defer root.deinit();

        self.forest.chores.write(&root);
    }
};
