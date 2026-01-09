const std = @import("std");
const app = @import("app.zig");

pub fn main(init: std.process.Init) !void {
    var my_app = app.App{};
    try my_app.init(init);
    defer my_app.deinit();

    try my_app.parseOptions();

    if (my_app.loadConfig()) |_| {
        my_app.run();
    } else |err| {
        std.debug.print("Error: Could not load config due to '{}'.\n", .{err});
        std.debug.print("{s}", .{my_app.cli_args.help()});
    }
}
