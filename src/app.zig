const std = @import("std");

const Strange = @import("rubr").strange.Strange;
const strings = @import("rubr").strings;
const walker = @import("rubr").walker;
const ignore = @import("rubr").ignore;

const cli = @import("cli.zig");
const tkn = @import("tkn.zig");
const mero = @import("mero.zig");
const cfg = @import("cfg.zig");

pub const Error = error{
    UnknownFileType,
};

pub const App = struct {
    options: *const cli.Options,
    config: *const cfg.Config,
    ma: std.mem.Allocator,

    pub fn run(self: App) !void {
        const start_time = std.time.milliTimestamp();
        try self._run();
        const stop_time = std.time.milliTimestamp();
        std.debug.print("Duration: {}ms\n", .{stop_time - start_time});
    }

    fn _run(self: App) !void {
        for (self.config.groves.items) |grove| {
            if (!strings.contains(u8, self.options.groves.items, grove.name))
                // Skip this grove
                continue;

            std.debug.print("Processing {s} {s}\n", .{ grove.name, grove.path });

            var w = try walker.Walker.init(self.ma);
            defer w.deinit();

            const String = std.ArrayList(u8);
            var content = String.init(self.ma);
            defer content.deinit();

            var cb = struct {
                const Self = @This();
                const Buffer = std.ArrayList(u8);

                outer: *const App,
                grove: *const cfg.Grove,
                content: *String,
                ma: std.mem.Allocator,

                file_count: usize = 0,
                byte_count: usize = 0,
                token_count: usize = 0,
                out: std.fs.File.Writer = undefined,

                pub fn init(slf: *Self) void {
                    slf.out = std.io.getStdOut().writer();
                }

                pub fn call(my: *Self, dir: std.fs.Dir, path: []const u8, offsets: walker.Offsets) !void {
                    const name = path[offsets.name..];

                    if (my.grove.include) |include| {
                        const ext = std.fs.path.extension(name);
                        if (!strings.contains(u8, include.items, ext))
                            // Skip this extension
                            return;
                    }

                    const file = try dir.openFile(name, .{});
                    defer file.close();

                    const stat = try file.stat();

                    const size_is_ok = if (my.grove.max_size) |max_size| stat.size < max_size else true;
                    if (!size_is_ok)
                        return;

                    if (my.grove.max_count) |max_count|
                        if (my.file_count >= max_count)
                            return;

                    if (my.outer.options.do_print) {
                        try my.out.print("{s}\n", .{path});
                        if (false) {
                            try my.out.print("  base {s}\n", .{path[offsets.base..]});
                            try my.out.print("  name {s}\n", .{path[offsets.name..]});
                        }
                    }

                    // Read data: 160ms
                    {
                        try my.content.resize(stat.size);
                        my.byte_count += try file.readAll(my.content.items);
                    }
                    my.file_count += 1;

                    if (my.outer.options.do_scan) {
                        var tokenizer = tkn.Tokenizer.init(my.content.items);
                        // Iterate over tokens: 355ms-160ms
                        while (tokenizer.next()) |_| {
                            my.token_count += 1;
                        }
                    }

                    if (my.outer.options.do_parse) {
                        const my_ext = std.fs.path.extension(name);
                        if (mero.Language.from_extension(my_ext)) |language| {
                            var parser = mero.Parser.init(my.ma, language);
                            var root = try parser.parse(my.content.items);
                            defer root.deinit();
                            // for (parser.lines.items) |line| {
                            //     std.debug.print("Line: {s}\n", .{line});
                            // }
                        } else {
                            std.debug.print("Unsupported extension '{s}' for '{}' '{s}'\n", .{ my_ext, dir, path });
                            // return Error.UnknownFileType;
                        }
                    }
                }
            }{ .outer = &self, .grove = &grove, .content = &content, .ma = self.ma };
            cb.init();

            // const dir = try std.fs.cwd().openDir(grove.path, .{});
            const dir = try std.fs.openDirAbsolute(grove.path, .{});
            std.debug.print("folder: {s} {}\n", .{ grove.path, dir });

            try w.walk(dir, &cb);
            std.debug.print("file_count: {}, byte_count {}MB, token_count {}\n", .{ cb.file_count, cb.byte_count / 1000000, cb.token_count });
        }
    }
};
