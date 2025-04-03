const std = @import("std");

const cli = @import("rubr").cli;

const Error = error{
    CouldNotFindExeName,
    UnknownArgument,
    ModeAlreadySet,
};

pub const Mode = enum {
    Ls,
    Lsp,
};

pub const Options = struct {
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

    args: cli.Args = undefined,
    aa: std.heap.ArenaAllocator = undefined,

    pub fn init(self: *Self, ma: std.mem.Allocator) !void {
        self.args = cli.Args.init(ma);
        try self.args.setupFromOS();

        self.aa = std.heap.ArenaAllocator.init(ma);
        self.groves = Strings.init(self.aa.allocator());
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
                    try self.groves.append(x.arg);
            } else if (arg.is("-l", "--log")) {
                if (self.args.pop()) |x|
                    self.logfile = x.arg;
            } else if (arg.is("-s", "--scan")) {
                self.do_scan = true;
            } else if (arg.is("-p", "--parse")) {
                self.do_parse = true;
            } else if (arg.is("ls", "ls")) {
                if (self.mode != null)
                    return Error.ModeAlreadySet;
                self.mode = Mode.Ls;
            } else if (arg.is("lsp", "lsp")) {
                if (self.mode != null)
                    return Error.ModeAlreadySet;
                self.mode = Mode.Lsp;
            } else {
                std.debug.print("Unknown argument '{s}'\n", .{arg.arg});
                return error.UnknownArgument;
            }
        }
    }

    pub fn help(_: Self) []const u8 {
        const msg = "" ++
            "chimp <options> <command>\n" ++
            "  Options:\n" ++
            "    -h  --help           Print this help\n" ++
            "    -v  --verbose LEVEL  Verbosity LEVEL [optional, default 0]\n" ++
            "    -g  --grove   NAME   Use grove NAME\n" ++
            "    -l  --log     FILE   Log to FILE\n" ++
            "    -s  --scan           Scan\n" ++
            "    -p  --parse          Parse\n" ++
            "  Commands:\n" ++
            "    ls                   List\n" ++
            "    lsp                  Lsp server\n" ++
            "Developed by Geert Fannes\n";
        return msg;
    }
};
