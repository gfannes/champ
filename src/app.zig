const std = @import("std");

const Options = @import("cli.zig").Options;
const Strange = @import("rubr").strange.Strange;
const walker = @import("rubr").walker;

pub const App = struct {
    options: *const Options,

    ma: std.mem.Allocator,

    pub fn init(options: *const Options, ma: std.mem.Allocator) App {
        return App{ .options = options, .ma = ma };
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

            var cb = struct {
                const Buffer = std.ArrayList(u8);

                out: std.fs.File.Writer,
                buffer: Buffer = undefined,
                total: usize = 0,
                adler: std.hash.Adler32,

                pub fn init(ma: std.mem.Allocator) @This() {
                    return .{ .out = std.io.getStdOut().writer(), .buffer = Buffer.init(ma), .adler = std.hash.Adler32.init() };
                }
                pub fn deinit(my: *@This()) void {
                    my.buffer.deinit();
                }

                pub fn call(my: *@This(), dir: std.fs.Dir, path: []const u8, offsets: walker.Offsets) !void {
                    if (true) {
                        // try my.out.print("{s}\n", .{path});
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
                                try my.buffer.resize(stat.size);
                                my.total += try file.readAll(my.buffer.items);
                                my.adler.update(my.buffer.items);
                            }
                        }
                    }
                }
            }.init(self.ma);
            defer cb.deinit();

            const dir = try std.fs.cwd().openDir(self.options.folder, .{});
            std.debug.print("folder: {s} {}\n", .{ self.options.folder, dir });

            try w.walk(dir, &cb);
            std.debug.print("Read {}MB adler {}\n", .{cb.total / 1000000, cb.adler.final()});
        }
    }
};
