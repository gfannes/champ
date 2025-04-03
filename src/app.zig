const std = @import("std");
const builtin = @import("builtin");

const Strange = @import("rubr").strange.Strange;
const strings = @import("rubr").strings;
const walker = @import("rubr").walker;
const ignore = @import("rubr").ignore;
const naft = @import("rubr").naft;

const cli = @import("cli.zig");
const tkn = @import("tkn.zig");
const mero = @import("mero.zig");
const cfg = @import("cfg.zig");
const lsp = @import("lsp.zig");

pub const Error = error{
    UnknownFileType,
    ModeNotSet,
    NotImplemented,
    CouldNotLoadConfig,
};

pub const App = struct {
    const Self = @This();
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    const FBA = std.heap.FixedBufferAllocator;

    start_time: i64 = undefined,

    stdout: std.fs.File = std.io.getStdOut(),
    stdoutw: std.fs.File.Writer = undefined,

    // gpa: 1075ms
    // fba: 640ms
    gpa: GPA = .{},
    gpaa: std.mem.Allocator = undefined,

    maybe_fba: ?FBA = null,

    ma: std.mem.Allocator = undefined,

    options: cli.Options = .{},
    maybe_outfile: ?std.fs.File = null,

    config_loader: ?cfg.Loader = null,
    config: cfg.Config = .{},

    pub fn init(self: *Self) !void {
        self.start_time = std.time.milliTimestamp();

        self.stdoutw = self.stdout.writer();

        self.gpaa = self.gpa.allocator();
        self.ma = self.gpaa;

        try self.options.init(self.gpaa);
    }
    pub fn deinit(self: *Self) void {
        if (self.config_loader) |*loader| loader.deinit();
        self.options.deinit();
        if (self.maybe_fba) |fba| self.gpaa.free(fba.buffer);
        if (self.gpa.deinit() == .leak) std.debug.print("Found memory leak\n", .{});

        {
            const stop_time = std.time.milliTimestamp();
            self.stdoutw.print("Duration: {}ms\n", .{stop_time - self.start_time}) catch {};
        }
        if (self.maybe_outfile) |outfile| outfile.close();
    }

    pub fn parseOptions(self: *Self) !void {
        self.options.parse() catch {
            self.options.print_help = true;
        };

        if (self.options.mode == cli.Mode.Lsp) {
            try self.options.setLogfile("/tmp/chimp.log");
        }

        if (self.options.logfile) |logfile| {
            const outfile = try std.fs.createFileAbsolute(logfile, .{});
            self.stdoutw = outfile.writer();
            self.maybe_outfile = outfile;
        }
    }

    pub fn loadConfig(self: *Self) !void {
        self.config_loader = try cfg.Loader.init(self.gpaa);
        const cfg_loader = &(self.config_loader orelse unreachable);

        const config_fp = if (builtin.os.tag == .macos) "/Users/geertf/.config/champ/config.zon" else "/home/geertf/.config/champ/config.zon";
        try cfg_loader.loadFromFile(config_fp);

        self.config = cfg_loader.config orelse return Error.CouldNotLoadConfig;

        if (self.config.max_memsize) |max_memsize| {
            try self.stdoutw.print("Running with max_memsize {}MB\n", .{max_memsize / 1024 / 1024});
            self.maybe_fba = FBA.init(try self.gpaa.alloc(u8, max_memsize));
            // Rewire self.ma to this fba
            self.ma = (self.maybe_fba orelse unreachable).allocator();
        }
    }

    pub fn run(self: Self) !void {
        if (self.options.print_help) {
            std.debug.print("{s}", .{self.options.help()});
        } else if (self.options.mode) |mode| {
            switch (mode) {
                cli.Mode.Ls => try self.run_ls(),
                cli.Mode.Lsp => try self.run_lsp(),
            }
        } else return Error.ModeNotSet;
    }

    fn run_ls(self: Self) !void {
        for (self.config.groves) |grove| {
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
                const Cb = @This();
                const Buffer = std.ArrayList(u8);

                outer: *const Self,
                grove: *const cfg.Grove,
                content: *String,
                ma: std.mem.Allocator,

                file_count: usize = 0,
                byte_count: usize = 0,
                token_count: usize = 0,

                pub fn call(my: *Cb, dir: std.fs.Dir, path: []const u8, offsets: walker.Offsets) !void {
                    // std.debug.print("Cb.call({s})\n", .{path});

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

                    if (my.outer.log(2)) |out| {
                        try out.print("{s}\n", .{path});
                    }
                    if (my.outer.log(3)) |out| {
                        try out.print("  base: {s}\n", .{path[offsets.base..]});
                        try out.print("  name: {s}\n", .{path[offsets.name..]});
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
                            errdefer root.deinit();

                            var mero_file = try mero.File.init(root, path, my.ma);
                            defer mero_file.deinit();

                            if (my.outer.log(1)) |out| {
                                var cb = struct {
                                    path: []const u8,
                                    o: @TypeOf(out),
                                    did_log_filename: bool = false,

                                    pub fn call(s: *@This(), amp: []const u8) !void {
                                        if (!s.did_log_filename) {
                                            try s.o.print("Filename: {s}\n", .{s.path});
                                            s.did_log_filename = true;
                                        }
                                        try s.o.print("{s}\n", .{amp});
                                    }
                                }{ .path = path, .o = out };
                                try mero_file.root.each_amp(&cb);
                            }
                            if (my.outer.log(4)) |out| {
                                var n = naft.Node.init(out.*);
                                mero_file.root.write(&n);
                            }
                        } else {
                            std.debug.print("Unsupported extension '{s}' for '{}' '{s}'\n", .{ my_ext, dir, path });
                            // return Error.UnknownFileType;
                        }
                    }
                }
            }{ .outer = &self, .grove = &grove, .content = &content, .ma = self.ma };

            // const dir = try std.fs.cwd().openDir(grove.path, .{});
            const dir = try std.fs.openDirAbsolute(grove.path, .{});
            std.debug.print("folder: {s} {}\n", .{ grove.path, dir });

            try w.walk(dir, &cb);
            std.debug.print("file_count: {}, byte_count {}MB, token_count {}\n", .{ cb.file_count, cb.byte_count / 1000000, cb.token_count });
        }
    }

    fn run_lsp(self: Self) !void {
        try self.stdoutw.print("Lsp server started {}\n", .{std.time.timestamp()});

        var cin = std.io.getStdIn();
        var cout = std.io.getStdOut();

        var server = lsp.Server.init(cin.reader(), cout.writer(), self.stdoutw, self.ma);
        defer server.deinit();

        var count: usize = 0;
        var do_continue = true;
        var init_ok = false;
        while (do_continue) : (count += 1) {
            try self.stdoutw.print("[Iteration](count:{})\n", .{count});

            const request = try server.receive();
            const dto = lsp.dto;
            if (request.id) |_| {
                if (std.mem.eql(u8, request.method, "initialize")) {
                    const result = dto.InitializeResult{
                        .capabilities = dto.ServerCapabilities{
                            .documentSymbolProvider = true,
                            .workspaceSymbolProvider = true,
                        },
                        .serverInfo = dto.ServerInfo{
                            .name = "chimp",
                            .version = "1.2.3",
                        },
                    };
                    try server.send(result);
                } else if (std.mem.eql(u8, request.method, "shutdown")) {
                    try server.send(null);
                } else if (std.mem.eql(u8, request.method, "textDocument/documentSymbol")) {
                    // &todo replace with actual symbols. Workspace symbols seems to not work in Helix.
                    const symbols = [_]dto.DocumentSymbol{ .{ .name = "abc" }, .{ .name = "def", .kind = 5 } };
                    try server.send(symbols);
                } else {
                    try self.stdoutw.print("Unhandled request '{s}'\n", .{request.method});
                }
            } else {
                if (std.mem.eql(u8, request.method, "textDocument/didOpen")) {
                    //
                } else if (std.mem.eql(u8, request.method, "initialized")) {
                    init_ok = true;
                } else if (std.mem.eql(u8, request.method, "exit")) {
                    do_continue = false;
                } else {
                    try self.stdoutw.print("Unhandled notification '{s}'\n", .{request.method});
                }
            }
        }
    }

    fn log(self: Self, level: usize) ?*const std.fs.File.Writer {
        if (self.options.verbose >= level)
            return &self.stdoutw;
        return null;
    }
};
