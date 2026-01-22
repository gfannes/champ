// Command-line interface arguments

const std = @import("std");
const rubr = @import("rubr");
const Env = rubr.Env;

const Error = error{
    CouldNotFindExeName,
    UnknownMode,
    ModeDoesNotSupportExtra,
    ExpectedNumber,
    ExpectedPrio,
};

pub const Mode = enum {
    Search,
    Lsp,
    Plan,
    Check,
    Perf,
    Export,
    Test,
};

pub const Args = struct {
    const Self = @This();
    const Strings = std.ArrayList([]const u8);

    env: Env,

    exe_name: []const u8 = &.{},
    print_help: bool = false,
    groves: Strings = undefined,
    logfile: ?[]const u8 = null,
    do_scan: bool = false,
    do_parse: bool = false,
    verbose: usize = 0,
    mode: ?Mode = null,
    prio: ?[]const u8 = null,
    reverse: bool = false,
    details: bool = false,
    output: ?[]const u8 = null,
    extra: Strings = undefined,

    args: rubr.cli.Args = undefined,

    pub fn init(self: *Self, os_args: std.process.Args) !void {
        self.args = rubr.cli.Args{ .env = self.env };
        try self.args.setupFromOS(os_args);

        self.groves = Strings{};
        self.extra = Strings{};
    }
    pub fn deinit(_: *Self) void {}

    pub fn setLogfile(self: *Self, logfile: []const u8) !void {
        self.logfile = try self.env.aa.dupe(u8, logfile);
    }

    pub fn parse(self: *Self) !void {
        self.exe_name = (self.args.pop() orelse return error.CouldNotFindExeName).arg;

        while (self.args.pop()) |arg| {
            if (arg.is("-h", "--help")) {
                self.print_help = true;
            } else if (arg.is("-v", "--verbose")) {
                const v = self.args.pop() orelse return error.ExpectedNumber;
                self.verbose = try v.as(usize);
            } else if (arg.is("-g", "--grove")) {
                if (self.args.pop()) |x|
                    try self.groves.append(self.env.aa, x.arg);
            } else if (arg.is("-o", "--output")) {
                if (self.args.pop()) |x|
                    self.output = x.arg;
            } else if (arg.is("-l", "--log")) {
                if (self.args.pop()) |x|
                    self.logfile = x.arg;
            } else if (arg.is("-s", "--scan")) {
                self.do_scan = true;
            } else if (arg.is("-P", "--parse")) {
                self.do_parse = true;
            } else if (arg.is("-p", "--prio")) {
                const prio = self.args.pop() orelse return error.ExpectedPrio;
                self.prio = prio.arg;
            } else if (arg.is("-r", "--reverse")) {
                self.reverse = true;
            } else if (arg.is("-d", "--details")) {
                self.details = true;
            } else {
                if (self.mode) |mode| {
                    switch (mode) {
                        .Search, .Export, .Plan, .Test => try self.extra.append(self.env.aa, arg.arg),
                        else => {
                            std.debug.print("{} does not support extra argument '{s}'\n", .{ mode, arg.arg });
                            return error.ModeDoesNotSupportExtra;
                        },
                    }
                } else if (arg.is("lsp", "lsp")) {
                    self.mode = .Lsp;
                } else if (arg.is("se", "search")) {
                    self.mode = .Search;
                } else if (arg.is("ex", "export")) {
                    self.mode = .Export;
                } else if (arg.is("pl", "plan")) {
                    self.mode = .Plan;
                } else if (arg.is("ch", "check")) {
                    self.mode = .Check;
                } else if (arg.is("perf", "perf")) {
                    self.mode = .Perf;
                } else if (arg.is("test", "test")) {
                    self.mode = .Test;
                } else {
                    std.debug.print("Unknown mode '{s}'\n", .{arg.arg});
                    return error.UnknownMode;
                }
            }
        }
    }

    pub fn help(_: Self) []const u8 {
        // &:zig:build:info Couple this with info from build.zig.zon
        const msg = "" ++
            "champ <options> <command>\n" ++
            "  Options:\n" ++
            "    -h  --help           Print this help\n" ++
            "    -v  --verbose LEVEL  Verbosity LEVEL [optional, default 0]\n" ++
            "    -g  --grove   NAME   Use grove NAME\n" ++
            "    -l  --log     FILE   Log to FILE\n" ++
            "    -s  --scan           Scan\n" ++
            "    -P  --parse          Parse\n" ++
            "    -p  --prio           Prio (top: a0)\n" ++
            "    -r  --reverse        Reverse\n" ++
            "    -d  --details        Details\n" ++
            "  Commands:\n" ++
            "    lsp                  Lsp server\n" ++
            "    se/search            Search\n" ++
            "    ex/export            Export\n" ++
            "    pl/plan              Plan\n" ++
            "    ch/check             Check\n" ++
            "    perf                 Performance tests\n" ++
            "    test                 Test\n" ++
            "Developed by Geert Fannes\n";
        return msg;
    }
};
