const std = @import("std");

const CliError = error{
    CouldNotFindExeName,
    UnknownArgument,
};

pub const Options = struct {
    const Strings = std.ArrayList([]const u8);

    exe_name: []const u8 = &.{},
    print_help: bool = false,
    groves: Strings = undefined,
    do_scan: bool = false,
    do_parse: bool = false,
    verbose: usize = 0,

    _args: [][*:0]u8 = &.{},
    _aa: std.heap.ArenaAllocator = undefined,

    pub fn init(self: *Options, ma: std.mem.Allocator) void {
        self._args = std.os.argv;
        self._aa = std.heap.ArenaAllocator.init(ma);
        self.groves = Strings.init(self._aa.allocator());
    }
    pub fn deinit(self: Options) void {
        self._aa.deinit();
    }

    pub fn parse(self: *Options) !void {
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
            } else if (arg.is("-s", "--scan")) {
                self.do_scan = true;
            } else if (arg.is("-p", "--parse")) {
                self.do_parse = true;
            } else {
                std.debug.print("Unknown argument '{s}'\n", .{arg.arg});
                return error.UnknownArgument;
            }
        }
    }

    pub fn help(_: Options) []const u8 {
        const msg = "" ++
            "chimp <options>\n" ++
            "    -h  --help           Print this help\n" ++
            "    -v  --verbose LEVEL  Verbosity LEVEL [optional, default 0]\n" ++
            "    -g  --grove   NAME   Use grove NAME\n" ++
            "    -s  --scan           Scan\n" ++
            "    -p  --parse          Parse\n" ++
            "Developed by Geert Fannes\n";
        return msg;
    }

    fn _pop(self: *Options) ?Arg {
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
