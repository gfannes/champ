const std = @import("std");

const Options = @import("cli.zig").Options;
const App = @import("app.zig").App;

pub fn main() !void {
    var gp = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gp.deinit();
    const gpa = gp.allocator();

    const buffer = try gpa.alloc(u8, 1024 * 1024 * 1024);
    defer gpa.free(buffer);
    var fb = std.heap.FixedBufferAllocator.init(buffer);
    const fba = fb.allocator();

    // gpa: 1075ms
    // fba: 640ms
    const ma = if (false) gpa else fba;

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
        var app = try App.init(&options, ma);
        defer app.deinit();

        try app.run();
    }
}
