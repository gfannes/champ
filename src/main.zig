const std = @import("std");

const cli = @import("cli.zig");
const cfg = @import("cfg.zig");
const app = @import("app.zig");

pub fn main() !void {
    var stdout = std.io.getStdOut();
    var out = stdout.writer();

    var gp = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gp.deinit();
    const gpa = gp.allocator();

    var options = cli.Options{};
    options.init(gpa);
    defer options.deinit();

    options.parse() catch {
        options.print_help = true;
    };

    if (options.mode == cli.Mode.Lsp) {
        try options.setLogfile("/tmp/chimp.log");
    }

    var maybe_outfile: ?std.fs.File = null;
    defer {
        if (maybe_outfile) |outfile| outfile.close();
    }
    if (options.logfile) |logfile| {
        const outfile = try std.fs.createFileAbsolute(logfile, .{});
        out = outfile.writer();
        maybe_outfile = outfile;
    }

    var config = cfg.Config.init(gpa);
    defer config.deinit();
    try config.loadTestDefaults();

    // gpa: 1075ms
    // fba: 640ms
    var ma = gpa;
    var maybe_fb: ?std.heap.FixedBufferAllocator = null;
    defer if (maybe_fb) |fb| gpa.free(fb.buffer);
    if (config.max_memsize) |max_memsize| {
        try out.print("Running with max_memsize {}MB\n", .{max_memsize / 1024 / 1024});
        maybe_fb = std.heap.FixedBufferAllocator.init(try gpa.alloc(u8, max_memsize));
        if (maybe_fb) |*fb| ma = fb.allocator();
    }

    if (options.print_help) {
        std.debug.print("{s}", .{options.help()});
    } else {
        var my_app = app.App{ .options = &options, .config = &config, .out = &out, .ma = ma };
        try my_app.run();
    }
}
