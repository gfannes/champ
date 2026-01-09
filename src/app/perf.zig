const std = @import("std");

const rubr = @import("rubr");
const strings = rubr.strings;
const walker = rubr.walker;
const naft = rubr.naft;
const Env = rubr.Env;

const cfg = @import("../cfg.zig");
const tkn = @import("../tkn.zig");
const mero = @import("../mero.zig");

pub const Perf = struct {
    const Self = @This();

    env: Env,
    config: *const cfg.file.Config,
    cli_args: *const cfg.cli.Args,

    pub fn call(self: Self) !void {
        for (self.config.groves) |grove| {
            if (!strings.contains(u8, self.cli_args.groves.items, grove.name))
                // Skip this grove
                continue;

            std.debug.print("Processing {s} {s}\n", .{ grove.name, grove.path });

            var w = walker.Walker{ .env = self.env };
            defer w.deinit();

            const String = std.ArrayList(u8);
            var content = String{};
            defer content.deinit(self.env.a);

            var cb = struct {
                const Cb = @This();
                const Buffer = std.ArrayList(u8);

                env: Env,
                outer: *const Self,
                grove: *const cfg.file.Grove,
                content: *String,

                file_count: usize = 0,
                byte_count: usize = 0,
                token_count: usize = 0,

                pub fn call(my: *Cb, dir: std.Io.Dir, path: []const u8, maybe_offsets: ?walker.Offsets, kind: walker.Kind) !void {
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

                    const file = try dir.openFile(my.env.io, name, .{});
                    defer file.close(my.env.io);

                    const stat = try file.stat(my.env.io);

                    const size_is_ok = if (my.grove.max_size) |max_size| stat.size < max_size else true;
                    if (!size_is_ok)
                        return;

                    if (my.grove.max_count) |max_count|
                        if (my.file_count >= max_count)
                            return;

                    if (my.env.log.level(2)) |out| {
                        try out.print("{s}\n", .{path});
                    }
                    if (my.env.log.level(3)) |out| {
                        try out.print("  base: {s}\n", .{path[offsets.base..]});
                        try out.print("  name: {s}\n", .{path[offsets.name..]});
                    }

                    // Read data: 160ms
                    {
                        try my.content.resize(my.env.a, stat.size);
                        var buf: [1024]u8 = undefined;
                        var reader = file.reader(my.env.io, &buf);
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
                            var tree = mero.Tree.init(my.env.a);
                            defer tree.deinit();

                            const f = try tree.addChild(null);
                            const n = f.data;
                            n.* = mero.Node{ .a = my.env.a };
                            n.type = mero.Node.Type.File;
                            n.language = language;
                            n.content = try n.a.dupe(u8, my.content.items);

                            var parser = try mero.Parser.init(my.env.a, f.id, &tree);

                            try parser.parse();
                        } else {
                            std.debug.print("Unsupported extension '{s}' for '{}' '{s}'\n", .{ my_ext, dir, path });
                            // return Error.UnknownFileType;
                        }
                    }
                }
            }{ .env = self.env, .outer = &self, .grove = &grove, .content = &content };

            var dir = try std.Io.Dir.openDirAbsolute(self.env.io, grove.path, .{});
            defer dir.close(self.env.io);
            std.debug.print("folder: {s} {}\n", .{ grove.path, dir });

            try w.walk(dir, &cb);
            std.debug.print("file_count: {}, byte_count {}MB, token_count {}\n", .{ cb.file_count, cb.byte_count / 1000000, cb.token_count });
        }
    }
};
