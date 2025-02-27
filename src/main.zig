const std = @import("std");

const Options = @import("cli.zig").Options;
const App = @import("app.zig").App;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ma = gpa.allocator();

    var options = Options.init(ma);
    defer options.deinit();

    options.parse() catch {
        options.print_help = true;
    };

    if (options.print_help) {
        std.debug.print("{s}", .{options.help()});
    } else {
        var app = App.init(&options, ma);
        defer app.deinit();

        try app.run();
    }
}
