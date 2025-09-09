const std = @import("std");
const builtin = @import("builtin");

const Strange = @import("rubr").strange.Strange;
const strings = @import("rubr").strings;
const walker = @import("rubr").walker;
const ignore = @import("rubr").ignore;
const naft = @import("rubr").naft;
const Log = @import("rubr").log.Log;

const tkn = @import("tkn.zig");
const mero = @import("mero.zig");
const cfg = @import("cfg.zig");

const Lsp = @import("app/lsp.zig").Lsp;
const Search = @import("app/search.zig").Search;
const Perf = @import("app/perf.zig").Perf;
const Test = @import("app/test.zig").Test;

pub const Error = error{
    UnknownFileType,
    ModeNotSet,
    NotImplemented,
    CouldNotLoadConfig,
};

// Holds all the data that should not be moved anymore
pub const App = struct {
    const Self = @This();
    const GPA = std.heap.GeneralPurposeAllocator(.{});
    const FBA = std.heap.FixedBufferAllocator;

    start_time: i64 = undefined,

    log: Log = .{},
    buffer: [1024]u8 = undefined,
    stdoutw: std.fs.File.Writer = undefined,
    io: *std.Io.Writer = undefined,

    // gpa: 1075ms
    // fba: 640ms
    gpa: GPA = .{},
    gpaa: std.mem.Allocator = undefined,

    maybe_fba: ?FBA = null,

    a: std.mem.Allocator = undefined,

    cli_args: cfg.cli.Args = .{},

    config_loader: ?cfg.file.Loader = null,
    config: cfg.file.Config = .{},

    // Instance should not be moved after init()
    pub fn init(self: *Self) !void {
        self.start_time = std.time.milliTimestamp();

        self.log.init();
        self.stdoutw = std.fs.File.stdout().writer(&self.buffer);
        self.io = &self.stdoutw.interface;

        self.gpaa = self.gpa.allocator();
        self.a = self.gpaa;

        try self.cli_args.init(self.gpaa);
    }
    pub fn deinit(self: *Self) void {
        if (self.config_loader) |*loader| loader.deinit();
        self.cli_args.deinit();
        if (self.maybe_fba) |fba| self.gpaa.free(fba.buffer);
        if (self.gpa.deinit() == .leak) std.debug.print("Found memory leak\n", .{});

        {
            const stop_time = std.time.milliTimestamp();
            self.io.print("Duration: {}ms\n", .{stop_time - self.start_time}) catch {};
        }
        self.log.deinit();
    }

    pub fn parseOptions(self: *Self) !void {
        self.cli_args.parse() catch |err| {
            std.debug.print("{}\n", .{err});
            self.cli_args.print_help = true;
        };

        if (self.cli_args.logfile) |logfile| {
            try self.log.toFile(logfile);
        } else if (self.cli_args.mode == cfg.cli.Mode.Lsp) {
            // &:zig:build:info Couple filename with build.zig.zon#name
            // &cleanup:log &todo Cleanup old log files
            try self.log.toFile("/tmp/champ-%.log");
        }
    }

    pub fn loadConfig(self: *Self) !bool {
        self.config_loader = try cfg.file.Loader.init(self.gpaa);
        const cfg_loader = &(self.config_loader orelse unreachable);

        // &todo: Replace hardcoded HOME folder
        // &:zig:build:info Couple filename with build.zig.zon#name
        const config_fp = if (builtin.os.tag == .macos) "/Users/geertf/.config/champ/config.zon" else "/home/geertf/.config/champ/config.zon";
        const ret = try cfg_loader.loadFromFile(config_fp);

        self.config = cfg_loader.config orelse return Error.CouldNotLoadConfig;

        return ret;
    }

    pub fn run(self: Self) !void {
        if (self.cli_args.print_help) {
            std.debug.print("{s}", .{self.cli_args.help()});
        } else if (self.cli_args.mode) |mode| {
            switch (mode) {
                cfg.cli.Mode.Lsp => {
                    var obj = Lsp{
                        .config = &self.config,
                        .cli_args = &self.cli_args,
                        .log = &self.log,
                        .a = self.a,
                    };
                    try obj.init();
                    defer obj.deinit();
                    try obj.call();
                },
                cfg.cli.Mode.Search => {
                    var obj = Search{
                        .config = &self.config,
                        .cli_args = &self.cli_args,
                        .log = &self.log,
                        .a = self.a,
                    };
                    try obj.init();
                    defer obj.deinit();
                    try obj.call();
                },
                cfg.cli.Mode.Perf => {
                    var obj = Perf{
                        .config = &self.config,
                        .cli_args = &self.cli_args,
                        .log = &self.log,
                        .a = self.a,
                    };
                    try obj.call();
                },
                cfg.cli.Mode.Test => {
                    var obj = Test{
                        .config = &self.config,
                        .cli_args = &self.cli_args,
                        .log = &self.log,
                        .a = self.a,
                    };
                    try obj.init();
                    defer obj.deinit();
                    try obj.call();
                },
            }
        } else return Error.ModeNotSet;
    }
};
