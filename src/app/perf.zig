const std = @import("std");

const strings = @import("rubr").strings;
const walker = @import("rubr").walker;
const naft = @import("rubr").naft;
const Log = @import("rubr").log.Log;

const cfg = @import("../cfg.zig");
const tkn = @import("../tkn.zig");
const mero = @import("../mero.zig");

pub const Perf = struct {
    const Self = @This();

    config: *const cfg.file.Config,
    cli_args: *const cfg.cli.Args,
    log: *const Log,
    a: std.mem.Allocator,
    io: std.Io,

    pub fn call(self: Self) !void {
        for (self.config.groves) |grove| {
            if (!strings.contains(u8, self.cli_args.groves.items, grove.name))
                // Skip this grove
                continue;

            std.debug.print("Processing {s} {s}\n", .{ grove.name, grove.path });

            var w = walker.Walker.init(self.a, self.io);
            defer w.deinit();

            const String = std.ArrayList(u8);
            var content = String{};
            defer content.deinit(self.a);

            var cb = struct {
                const Cb = @This();
                const Buffer = std.ArrayList(u8);

                outer: *const Self,
                grove: *const cfg.file.Grove,
                content: *String,
                a: std.mem.Allocator,
                io: std.Io,

                file_count: usize = 0,
                byte_count: usize = 0,
                token_count: usize = 0,

                pub fn call(my: *Cb, dir: std.fs.Dir, path: []const u8, maybe_offsets: ?walker.Offsets, kind: walker.Kind) !void {
                    if (kind != walker.Kind.File)
                        return;

                    const offsets = maybe_offsets orelse return;
                    const name = path[offsets.name..];

                    if (my.grove.include) |include| {
                        const ext = std.fs.path.extension(name);
                        if (!strings.contains(u8, include, ext))
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

                    if (my.outer.log.level(2)) |out| {
                        try out.print("{s}\n", .{path});
                    }
                    if (my.outer.log.level(3)) |out| {
                        try out.print("  base: {s}\n", .{path[offsets.base..]});
                        try out.print("  name: {s}\n", .{path[offsets.name..]});
                    }

                    // Read data: 160ms
                    {
                        try my.content.resize(my.a, stat.size);
                        var buf: [1024]u8 = undefined;
                        var reader = file.reader(my.io, &buf);
                        try reader.interface.readSliceAll(my.content.items);
                        my.byte_count += stat.size;
                    }
                    my.file_count += 1;

                    if (my.outer.cli_args.do_scan) {
                        var tokenizer = tkn.Tokenizer.init(my.content.items);
                        // Iterate over tokens: 355ms-160ms
                        while (tokenizer.next()) |_| {
                            my.token_count += 1;
                        }
                    }

                    if (my.outer.cli_args.do_parse) {
                        const my_ext = std.fs.path.extension(name);
                        if (mero.Language.from_extension(my_ext)) |language| {
                            var tree = mero.Tree.init(my.a);
                            defer tree.deinit();

                            const f = try tree.addChild(null);
                            const n = f.data;
                            n.* = mero.Node.init(my.a);
                            n.type = mero.Node.Type.File;
                            n.language = language;
                            n.content = try n.a.dupe(u8, my.content.items);

                            var parser = try mero.Parser.init(f.id, &tree, my.a);
                            defer parser.deinit();

                            try parser.parse();
                        } else {
                            std.debug.print("Unsupported extension '{s}' for '{}' '{s}'\n", .{ my_ext, dir, path });
                            // return Error.UnknownFileType;
                        }
                    }
                }
            }{ .outer = &self, .grove = &grove, .content = &content, .a = self.a, .io = self.io };

            var dir = try std.fs.openDirAbsolute(grove.path, .{});
            defer dir.close();
            std.debug.print("folder: {s} {}\n", .{ grove.path, dir });

            try w.walk(dir, &cb);
            std.debug.print("file_count: {}, byte_count {}MB, token_count {}\n", .{ cb.file_count, cb.byte_count / 1000000, cb.token_count });
        }
    }
};
