const std = @import("std");

const Options = @import("cli.zig").Options;
const App = @import("app.zig").App;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const ma = gpa.allocator();

    var options = Options{};
    options.init(ma);
    defer options.deinit();

    options.parse() catch {
        options.print_help = true;
    };

    std.debug.print("After parsing\n", .{});

    if (options.print_help) {
        std.debug.print("{s}", .{options.help()});
    } else {
        var app = try App.make(&options, ma);
        defer app.deinit();

        try app.run();
    }
}
