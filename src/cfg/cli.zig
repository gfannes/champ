// Command-line interface arguments

const std = @import("std");
const rubr = @import("rubr");

const Error = error{
    CouldNotFindExeName,
    UnknownMode,
    ModeDoesNotSupportExtra,
};

pub const Mode = enum {
    Search,
    Lsp,
    Perf,
    Test,
};

pub const Args = struct {
    const Self = @This();
    const Strings = std.ArrayList([]const u8);

    exe_name: []const u8 = &.{},
    print_help: bool = false,
    groves: Strings = undefined,
    logfile: ?[]const u8 = null,
    do_scan: bool = false,
    do_parse: bool = false,
    verbose: usize = 0,
    mode: ?Mode = null,
    extra: Strings = undefined,

    args: rubr.cli.Args = undefined,
    aa: std.heap.ArenaAllocator = undefined,

    pub fn init(self: *Self, ma: std.mem.Allocator) !void {
        self.args = rubr.cli.Args.init(ma);
        try self.args.setupFromOS();

        self.aa = std.heap.ArenaAllocator.init(ma);
        self.groves = Strings{};
        self.extra = Strings{};
    }
    pub fn deinit(self: *Self) void {
        self.args.deinit();
        self.aa.deinit();
    }

    pub fn setLogfile(self: *Self, logfile: []const u8) !void {
        self.logfile = try self.aa.allocator().dupe(u8, logfile);
    }

    pub fn parse(self: *Self) !void {
        self.exe_name = (self.args.pop() orelse return error.CouldNotFindExeName).arg;

        while (self.args.pop()) |arg| {
            if (arg.is("-h", "--help")) {
                self.print_help = true;
            } else if (arg.is("-v", "--verbose")) {
                if (self.args.pop()) |x|
                    self.verbose = try x.as(usize);
            } else if (arg.is("-g", "--grove")) {
                if (self.args.pop()) |x|
                    try self.groves.append(self.aa.allocator(), x.arg);
            } else if (arg.is("-l", "--log")) {
                if (self.args.pop()) |x|
                    self.logfile = x.arg;
            } else if (arg.is("-s", "--scan")) {
                self.do_scan = true;
            } else if (arg.is("-p", "--parse")) {
                self.do_parse = true;
            } else {
                if (self.mode) |mode| {
                    switch (mode) {
                        Mode.Search, Mode.Test => try self.extra.append(self.aa.allocator(), arg.arg),
                        else => {
                            std.debug.print("{} does not support extra argument '{s}'\n", .{ mode, arg.arg });
                            return error.ModeDoesNotSupportExtra;
                        },
                    }
                } else if (arg.is("lsp", "lsp")) {
                    self.mode = Mode.Lsp;
                } else if (arg.is("se", "search")) {
                    self.mode = Mode.Search;
                } else if (arg.is("perf", "perf")) {
                    self.mode = Mode.Perf;
                } else if (arg.is("test", "test")) {
                    self.mode = Mode.Test;
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
            "    -p  --parse          Parse\n" ++
            "  Commands:\n" ++
            "    lsp                  Lsp server\n" ++
            "    se/search            Search\n" ++
            "    perf                 Performance tests\n" ++
            "    test                 Test\n" ++
            "Developed by Geert Fannes\n";
        return msg;
    }
};
