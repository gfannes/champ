const std = @import("std");

const cli = @import("cli.zig");
const cfg = @import("cfg.zig");
const app = @import("app.zig");

pub fn main() !void {
    var my_app = app.App{};
    try my_app.init();
    defer my_app.deinit();

    try my_app.parseOptions();
    try my_app.loadConfig();
    try my_app.run();
}
