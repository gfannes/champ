const std = @import("std");

const Strange = @import("rubr").strange.Strange;
const walker = @import("rubr").walker;
const ignore = @import("rubr").ignore;

const Options = @import("cli.zig").Options;
const tkn = @import("amp/tkn.zig");
const config = @import("config.zig");

pub const App = struct {
    options: *const Options,
    config: config.Config,

    ma: std.mem.Allocator,

    pub fn init(options: *const Options, ma: std.mem.Allocator) !App {
        var cfg = config.Config.init(ma);
        try cfg.loadDefault();
        return App{ .options = options, .config = cfg, .ma = ma };
    }

    pub fn deinit(self: *App) void {
        self.config.deinit();
    }

    pub fn run(self: App) !void {
        const start_time = std.time.milliTimestamp();
        try self._run();
        const stop_time = std.time.milliTimestamp();
        std.debug.print("Duration: {}ms\n", .{stop_time - start_time});
    }

    fn _run(self: App) !void {
        for (self.config.groves.items) |grove| {
            var found: bool = false;
            for (self.options.groves.items) |wanted_grove_name| {
                if (std.mem.eql(u8, grove.name, wanted_grove_name))
                    found = true;
            }
            if (!found)
                continue;

            std.debug.print("Processing {s}\n", .{grove.name});

            var w = try walker.Walker.init(self.ma);
            defer w.deinit();

            var cb = struct {
                const Buffer = std.ArrayList(u8);

                outer: *const App,
                grove: *const config.Grove,
                out: std.fs.File.Writer,
                file_count: usize = 0,
                byte_count: usize = 0,
                tokens: tkn.Tokens,

                pub fn init(outer: *const App, grv: *const config.Grove) @This() {
                    return .{ .outer = outer, .grove = grv, .out = std.io.getStdOut().writer(), .tokens = tkn.Tokens.init(outer.ma) };
                }
                pub fn deinit(my: *@This()) void {
                    my.tokens.deinit();
                }

                pub fn call(my: *@This(), dir: std.fs.Dir, path: []const u8, offsets: walker.Offsets) !void {
                    if (my.outer.options.do_print) {
                        try my.out.print("{s}\n", .{path});
                        if (false) {
                            try my.out.print("  base {s}\n", .{path[offsets.base..]});
                            try my.out.print("  name {s}\n", .{path[offsets.name..]});
                        }
                    }

                    {
                        const name = path[offsets.name..];

                        const file = try dir.openFile(name, .{});
                        defer file.close();

                        const stat = try file.stat();

                        const do_process = if (my.grove.max_size) |max_size| stat.size < max_size else true;
                        if (do_process) {
                            // Read data
                            {
                                const buf = try my.tokens.alloc_content(stat.size);
                                my.byte_count += try file.readAll(buf);
                            }

                            if (my.outer.options.do_scan)
                                try my.tokens.scan();

                            my.file_count += 1;
                        }
                    }
                }
            }.init(&self, &grove);
            defer cb.deinit();

            // const dir = try std.fs.cwd().openDir(grove.path, .{});
            const dir = try std.fs.openDirAbsolute(grove.path, .{});
            std.debug.print("folder: {s} {}\n", .{ grove.path, dir });

            try w.walk(dir, &cb);
            std.debug.print("file_count: {}, byte_count {}MB\n", .{ cb.file_count, cb.byte_count / 1000000 });
        }
    }
};
