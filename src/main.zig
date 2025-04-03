const std = @import("std");
const builtin = @import("builtin");

const cli = @import("cli.zig");
const cfg = @import("cfg.zig");
const app = @import("app.zig");

pub const Error = error{
    CouldNotLoadConfig,
};

pub fn main() !void {
    var stdout = std.io.getStdOut();
    var stdoutw = stdout.writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpaa = gpa.allocator();

    var options = cli.Options{};
    try options.init(gpaa);
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
        stdoutw = outfile.writer();
        maybe_outfile = outfile;
    }

    var cfg_loader = try cfg.Loader.init(gpaa);
    defer cfg_loader.deinit();

    const config_fp = if (builtin.os.tag == .macos) "/Users/geertf/.config/champ/config.zon" else "/home/geertf/.config/champ/config.zon";
    try cfg_loader.loadFromFile(config_fp);

    const config = cfg_loader.config orelse return Error.CouldNotLoadConfig;

    // gpa: 1075ms
    // fba: 640ms
    var ma = gpaa;
    var maybe_fb: ?std.heap.FixedBufferAllocator = null;
    defer if (maybe_fb) |fb| gpaa.free(fb.buffer);
    if (config.max_memsize) |max_memsize| {
        try stdoutw.print("Running with max_memsize {}MB\n", .{max_memsize / 1024 / 1024});
        maybe_fb = std.heap.FixedBufferAllocator.init(try gpaa.alloc(u8, max_memsize));
        if (maybe_fb) |*fb| ma = fb.allocator();
    }

    if (options.print_help) {
        std.debug.print("{s}", .{options.help()});
    } else {
        var my_app = app.App{ .options = &options, .config = &config, .out = &stdoutw, .ma = ma };
        try my_app.run();
    }
}
