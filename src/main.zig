const std = @import("std");

const cli = @import("cli.zig");
const config = @import("config.zig");
const App = @import("app.zig").App;

pub fn main() !void {
    var gp = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gp.deinit();
    const gpa = gp.allocator();

    var options = cli.Options{};
    options.init(gpa);
    defer options.deinit();

    var cfg = config.Config.init(gpa);
    defer cfg.deinit();
    try cfg.loadTestDefaults();

    // gpa: 1075ms
    // fba: 640ms
    var ma = gpa;
    var maybe_fb: ?std.heap.FixedBufferAllocator = null;
    defer if (maybe_fb) |fb| gpa.free(fb.buffer);
    if (cfg.max_memsize) |max_memsize| {
        maybe_fb = std.heap.FixedBufferAllocator.init(try gpa.alloc(u8, max_memsize));
        if (maybe_fb) |*fb| ma = fb.allocator();
    }

    options.parse() catch {
        options.print_help = true;
    };

    if (options.print_help) {
        std.debug.print("{s}", .{options.help()});
    } else {
        var app = App{ .options = &options, .config = &cfg, .ma = ma };
        try app.run();
    }
}
