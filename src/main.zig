const std = @import("std");
const cli = @import("cli.zig");
const app = @import("app.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ma = gpa.allocator();

    var options = cli.Options.init(ma);
    defer options.deinit();

    options.parse() catch {
        options.print_help = true;
    };

    if (options.print_help) {
        std.debug.print("{s}", .{options.help()});
    } else {
        const a = app.App{};
        _ = a;
    }
}
