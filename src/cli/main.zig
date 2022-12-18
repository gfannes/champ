const tui = @import("gubg/tui");
const std = @import("std");

pub fn main() !void {
    var term = try tui.Terminal.init(.{
        .timeout = false,
    });
    defer term.deinit();

    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        if (term.read_char()) |ch| {
            std.debug.print("{c}", .{ch});
        } else {
            std.debug.print("?", .{});
        }
    }

    std.debug.print("Everything went OK\n", .{});
}
