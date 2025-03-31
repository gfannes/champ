const std = @import("std");

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

    _args: [][*:0]u8 = &.{},
    _aa: std.heap.ArenaAllocator = undefined,

    pub fn init(self: *Self, ma: std.mem.Allocator) void {
        self._args = std.os.argv;
        self._aa = std.heap.ArenaAllocator.init(ma);
        self.groves = Strings.init(self._aa.allocator());
    }
    pub fn deinit(self: Self) void {
        self._aa.deinit();
    }

    pub fn setLogfile(self: *Self, logfile: []const u8) !void {
        self.logfile = try self._aa.allocator().dupe(u8, logfile);
    }

    pub fn parse(self: *Self) !void {
        self.exe_name = (self._pop() orelse return error.CouldNotFindExeName).arg;

        while (self._pop()) |arg| {
            if (arg.is("-h", "--help")) {
                self.print_help = true;
            } else if (arg.is("-v", "--verbose")) {
                if (self._pop()) |x|
                    self.verbose = try x.as(usize);
            } else if (arg.is("-g", "--grove")) {
                if (self._pop()) |x|
                    try self.groves.append(x.arg);
            } else if (arg.is("-l", "--log")) {
                if (self._pop()) |x|
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

    fn _pop(self: *Self) ?Arg {
        if (self._args.len == 0) return null;

        const ma = self._aa.allocator();
        const arg = ma.dupe(u8, std.mem.sliceTo(self._args[0], 0)) catch return null;
        self._args.ptr += 1;
        self._args.len -= 1;

        return Arg{ .arg = arg };
    }
};

const Arg = struct {
    const Self = @This();

    arg: []const u8,

    fn is(self: Arg, sh: []const u8, lh: []const u8) bool {
        return std.mem.eql(u8, self.arg, sh) or std.mem.eql(u8, self.arg, lh);
    }

    fn as(self: Self, T: type) !T {
        return try std.fmt.parseInt(T, self.arg, 10);
    }
};
