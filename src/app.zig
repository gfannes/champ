const std = @import("std");
const builtin = @import("builtin");

const rubr = @import("rubr");
const Strange = rubr.strange.Strange;
const strings = rubr.strings;
const walker = rubr.walker;
const ignore = rubr.ignore;
const naft = rubr.naft;
const Log = rubr.Log;
const Env = rubr.Env;

const tkn = @import("tkn.zig");
const mero = @import("mero.zig");
const cfg = @import("cfg.zig");

const Lsp = @import("app/lsp.zig").Lsp;
const Search = @import("app/search.zig").Search;
const Export = @import("app/export.zig").Export;
const Plan = @import("app/plan.zig").Plan;
const Check = @import("app/check.zig").Check;
const Perf = @import("app/perf.zig").Perf;
const Test = @import("app/test.zig").Test;
const Prio = @import("amp/Prio.zig");

pub const Error = error{
    UnknownFileType,
    ModeNotSet,
    NotImplemented,
    CouldNotLoadConfig,
    ExpectedForest,
};

// Holds all the data that should not be moved anymore
pub const App = struct {
    const Self = @This();
    const FBA = std.heap.FixedBufferAllocator;

    env_inst: Env.Instance = .{},
    env: Env = undefined,

    buffer: [1024]u8 = undefined,
    stdoutw: std.Io.File.Writer = undefined,
    witf: *std.Io.Writer = undefined,

    // gpa: 1075ms
    // fba: 640ms
    maybe_fba: ?FBA = null,

    cli_args: cfg.cli.Args = undefined,

    config_loader: ?cfg.file.Loader = null,
    config: cfg.file.Config = .{},
    fui: cfg.file.Fui = .{},

    maybe_forest: ?mero.Forest = null,

    // Instance should not be moved after init()
    pub fn init(self: *Self, os_init: std.process.Init) !void {
        self.env_inst.environ = os_init.minimal.environ;
        self.env_inst.init();
        self.env = self.env_inst.env();

        self.stdoutw = std.Io.File.stdout().writer(self.env.io, &self.buffer);
        self.witf = &self.stdoutw.interface;

        self.cli_args = .{ .env = self.env };
        try self.cli_args.init(os_init.minimal.args);
    }
    pub fn deinit(self: *Self) void {
        if (self.maybe_forest) |*forest|
            forest.deinit();

        if (self.config_loader) |*loader|
            loader.deinit();

        self.cli_args.deinit();

        if (self.maybe_fba) |fba|
            self.env.a.free(fba.buffer);

        {
            const duration_ms = self.env.duration_ns() / 1000 / 1000;
            self.witf.print("Duration: {}ms\n", .{duration_ms}) catch {};
        }
        self.env_inst.deinit();
    }

    pub fn parseOptions(self: *Self) !void {
        self.cli_args.parse() catch |err| {
            std.debug.print("{}\n", .{err});
            self.cli_args.print_help = true;
        };
        self.env_inst.log.setLevel(self.cli_args.verbose);

        if (self.cli_args.logfile) |logfile| {
            try self.env_inst.log.toFile(logfile, .{});
        } else if (self.cli_args.mode == cfg.cli.Mode.Lsp) {
            // &:zig:build:info Couple filename with build.zig.zon#name
            // &cleanup:log &todo Cleanup old log files
            try self.env_inst.log.toFile("/tmp/champ-%.log", .{ .autoclean = false });
        }
    }

    pub fn loadConfig(self: *Self) !bool {
        self.config_loader = try cfg.file.Loader.init(self.env);
        const cfg_loader = &(self.config_loader orelse unreachable);

        // &todo: Replace hardcoded HOME folder
        // &:zig:build:info Couple filename with build.zig.zon#name
        const config_fp = switch (builtin.os.tag) {
            .macos => "/Users/geertf/.config/champ/config.zon",
            .windows => "C:/Users/geertf/.config/champ/config.zon",
            else => "/home/geertf/.config/champ/config.zon",
        };
        const ret = try cfg_loader.loadFromFile(config_fp, .Config);

        self.config = cfg_loader.config orelse return Error.CouldNotLoadConfig;

        return ret;
    }

    pub fn run(self: *Self) void {
        self.run_() catch |err| {
            self.env.log.err("Received '{}'\n", .{err}) catch {};
        };
    }
    fn run_(self: *Self) !void {
        if (self.cli_args.print_help) {
            std.debug.print("{s}", .{self.cli_args.help()});
        } else if (self.cli_args.mode) |mode| {
            switch (mode) {
                cfg.cli.Mode.Lsp => {
                    var obj = Lsp{
                        .env = self.env,
                        .config = &self.config,
                        .fui = &self.fui,
                        .cli_args = &self.cli_args,
                    };
                    try obj.init();
                    defer obj.deinit();
                    try obj.call();
                },
                cfg.cli.Mode.Search => {
                    const forest = try self.loadForest();

                    var obj = Search{
                        .env = self.env,
                        .config = &self.config,
                        .forest = forest,
                    };
                    defer obj.deinit();

                    try obj.call(self.cli_args.extra.items, !self.cli_args.reverse);
                    try obj.show(self.cli_args.details > 0);
                },
                cfg.cli.Mode.Export => {
                    const forest = try self.loadForest();

                    var obj = Export{
                        .env = self.env,
                        .config = &self.config,
                        .cli_args = &self.cli_args,
                        .forest = forest,
                    };
                    defer obj.deinit();

                    try obj.call(self.cli_args.extra.items);
                },
                cfg.cli.Mode.Plan => {
                    const forest = try self.loadForest();

                    var obj = Plan{
                        .env = self.env,
                        .forest = forest,
                    };
                    defer obj.deinit();

                    const prio_threshold = if (self.cli_args.prio) |prio_str|
                        Prio.parse(prio_str, .{ .index = .Inf })
                    else
                        null;
                    try obj.call(prio_threshold, self.cli_args.extra.items, !self.cli_args.reverse);
                    try obj.show(self.cli_args.details > 0);
                },
                cfg.cli.Mode.Check => {
                    const forest = try self.loadForest();

                    var obj = Check{
                        .env = self.env,
                        .cli_args = &self.cli_args,
                        .forest = forest,
                    };
                    defer obj.deinit();

                    try obj.call();
                    try obj.show(self.cli_args.details);
                },
                cfg.cli.Mode.Perf => {
                    var obj = Perf{
                        .env = self.env,
                        .config = &self.config,
                        .cli_args = &self.cli_args,
                    };
                    try obj.call();
                },
                cfg.cli.Mode.Test => {
                    var obj = Test{
                        .env = self.env,
                        .config = &self.config,
                        .cli_args = &self.cli_args,
                    };
                    try obj.init();
                    defer obj.deinit();
                    try obj.call();
                },
            }
        } else return Error.ModeNotSet;
    }

    fn loadForest(self: *Self) !*mero.Forest {
        if (self.maybe_forest) |*forest|
            return forest;

        self.maybe_forest = mero.Forest{ .env = self.env };

        var forest = if (self.maybe_forest) |*ptr| ptr else return error.ExpectedForest;
        forest.init();
        try forest.load(&self.config, &self.cli_args);

        return forest;
    }
};
