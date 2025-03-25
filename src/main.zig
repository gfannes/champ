const std = @import("std");

const cli = @import("cli.zig");
const cfg = @import("cfg.zig");
const App = @import("app.zig").App;

pub fn main() !void {
    var gp = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gp.deinit();
    const gpa = gp.allocator();

    var options = cli.Options{};
    options.init(gpa);
    defer options.deinit();

    options.parse() catch {
        options.print_help = true;
    };

    var config = cfg.Config.init(gpa);
    defer config.deinit();
    try config.loadTestDefaults();

    // gpa: 1075ms
    // fba: 640ms
    var ma = gpa;
    var maybe_fb: ?std.heap.FixedBufferAllocator = null;
    defer if (maybe_fb) |fb| gpa.free(fb.buffer);
    if (config.max_memsize) |max_memsize| {
        std.debug.print("Running with max_memsize {}\n", .{max_memsize});
        maybe_fb = std.heap.FixedBufferAllocator.init(try gpa.alloc(u8, max_memsize));
        if (maybe_fb) |*fb| ma = fb.allocator();
    }

    if (options.print_help) {
        std.debug.print("{s}", .{options.help()});
    } else {
        var app = App{ .options = &options, .config = &config, .ma = ma };
        try app.run();
    }
}
