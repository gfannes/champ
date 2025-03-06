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

    pub fn deinit(_: *App) void {}

    pub fn run(self: App) !void {
        const start_time = std.time.milliTimestamp();
        try self._run();
        const stop_time = std.time.milliTimestamp();
        std.debug.print("Duration: {}ms\n", .{stop_time - start_time});
    }

    fn _run(self: App) !void {
        if (self.options.folder.len > 0) {
            var w = try walker.Walker.init(self.ma);
            defer w.deinit();

            var include = ignore.Ignore.init(self.ma);
            try include.addExt("zig");

            var cb = struct {
                const Buffer = std.ArrayList(u8);

                out: std.fs.File.Writer,
                file_count: usize = 0,
                byte_count: usize = 0,
                tokens: tkn.Tokens,
                include: ignore.Ignore,

                pub fn init(inc: ignore.Ignore, ma: std.mem.Allocator) @This() {
                    return .{ .out = std.io.getStdOut().writer(), .tokens = tkn.Tokens.init(ma), .include = inc };
                }
                pub fn deinit(my: *@This()) void {
                    my.tokens.deinit();
                }

                pub fn call(my: *@This(), dir: std.fs.Dir, path: []const u8, offsets: walker.Offsets) !void {
                    if (true) {
                        if (true or my.include.match(path[offsets.name..])) {
                            try my.out.print("{s}\n", .{path});
                            if (false) {
                                try my.out.print("  base {s}\n", .{path[offsets.base..]});
                                try my.out.print("  name {s}\n", .{path[offsets.name..]});
                            }
                            if (true) {
                                const name = path[offsets.name..];

                                const file = try dir.openFile(name, .{});
                                defer file.close();

                                const stat = try file.stat();

                                if (false or stat.size <= 256000) {
                                    {
                                        const buf = try my.tokens.alloc_content(stat.size);
                                        my.byte_count += try file.readAll(buf);
                                    }
                                    try my.tokens.scan();
                                    my.file_count += 1;
                                }
                            }
                        }
                    }
                }
            }.init(include, self.ma);
            defer cb.deinit();

            const dir = try std.fs.cwd().openDir(self.options.folder, .{});
            std.debug.print("folder: {s} {}\n", .{ self.options.folder, dir });

            try w.walk(dir, &cb);
            std.debug.print("file_count: {}, byte_count {}MB\n", .{ cb.file_count, cb.byte_count / 1000000 });
        }
    }
};
