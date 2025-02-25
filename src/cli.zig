const std = @import("std");
const os = std.os;

const Strange = @import("rubr").strange.Strange;

const CliError = error{
    CouldNotFindExeName,
    UnknownArgument,
};

pub const Options = struct {
    _aa: std.heap.ArenaAllocator,
    _args: [][*:0]u8,

    exe_name: []const u8 = &[_]u8{},
    print_help: bool = false,

    pub fn init(ma: std.mem.Allocator) Options {
        return Options{ ._aa = std.heap.ArenaAllocator.init(ma), ._args = os.argv };
    }
    pub fn deinit(self: Options) void {
        self._aa.deinit();
    }

    pub fn parse(self: *Options) !void {
        self.exe_name = (self._pop() orelse return error.CouldNotFindExeName).arg;

        while (self._pop()) |arg| {
            if (arg.is("-h", "--help")) {
                self.print_help = true;
            } else {
                std.debug.print("Unknown argument '{s}'\n", .{arg.arg});
                return error.UnknownArgument;
            }
        }
    }

    pub fn help(_: Options) []const u8 {
        const msg = "" ++
            "chimp <options>\n" ++
            "    -h  --help       Print this help\n" ++
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
    arg: []const u8,

    fn is(self: Arg, sh: []const u8, lh: []const u8) bool {
        return std.mem.eql(u8, self.arg, sh) or std.mem.eql(u8, self.arg, lh);
    }
};
