const std = @import("std");
const builtin = @import("builtin");

const Strange = @import("rubr").strange.Strange;
const strings = @import("rubr").strings;
const walker = @import("rubr").walker;
const ignore = @import("rubr").ignore;
const naft = @import("rubr").naft;
const Log = @import("rubr").log.Log;

const cli = @import("cli.zig");
const tkn = @import("tkn.zig");
const mero = @import("mero.zig");
const cfg = @import("cfg.zig");

const Perf = @import("app/perf.zig").Perf;
const Lsp = @import("app/lsp.zig").Lsp;
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
    stdout: std.fs.File = std.io.getStdOut(),
    stdoutw: std.fs.File.Writer = undefined,

    // gpa: 1075ms
    // fba: 640ms
    gpa: GPA = .{},
    gpaa: std.mem.Allocator = undefined,

    maybe_fba: ?FBA = null,

    a: std.mem.Allocator = undefined,

    options: cli.Options = .{},

    config_loader: ?cfg.Loader = null,
    config: cfg.Config = .{},

    // Instance should not be moved after init()
    pub fn init(self: *Self) !void {
        self.start_time = std.time.milliTimestamp();

        self.log.init();
        self.stdoutw = self.stdout.writer();

        self.gpaa = self.gpa.allocator();
        self.a = self.gpaa;

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
        self.log.deinit();
    }

    pub fn parseOptions(self: *Self) !void {
        self.options.parse() catch {
            self.options.print_help = true;
        };

        if (self.options.logfile) |logfile| {
            try self.log.toFile(logfile);
        } else if (self.options.mode == cli.Mode.Lsp) {
            try self.log.toFile("/tmp/chimp.log");
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
            self.a = (self.maybe_fba orelse unreachable).allocator();
        }
    }

    pub fn run(self: Self) !void {
        if (self.options.print_help) {
            std.debug.print("{s}", .{self.options.help()});
        } else if (self.options.mode) |mode| {
            switch (mode) {
                cli.Mode.Perf => {
                    var perf = Perf{
                        .config = &self.config,
                        .options = &self.options,
                        .log = &self.log,
                        .a = self.a,
                    };
                    try perf.call();
                },
                cli.Mode.Lsp => {
                    var lsp = Lsp{
                        .config = &self.config,
                        .options = &self.options,
                        .log = &self.log,
                        .a = self.a,
                    };
                    try lsp.init();
                    try lsp.call();
                },
                cli.Mode.Test => {
                    var tst = Test{
                        .config = &self.config,
                        .options = &self.options,
                        .log = &self.log,
                        .a = self.a,
                    };
                    try tst.init();
                    try tst.call();
                },
            }
        } else return Error.ModeNotSet;
    }
};
