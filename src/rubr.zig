// Output from `rake export[Env,strng,strings,naft,walker,slc,Log,idx,cli,datex,tree,lsp,fuzz,algo,opt,ansi]` from https://github.com/gfannes/rubr from 2026-03-15

const std = @import("std");
const builtin = @import("builtin");

// Export from 'src/Env.zig'
pub const Env = struct {
    const Env_ = @This();
    
    // General purpose allocator
    a: std.mem.Allocator = undefined,
    // Arena allocator
    aa: std.mem.Allocator = undefined,
    
    io: std.Io = undefined,
    envmap: *const std.process.Environ.Map = undefined,
    
    log: *const Log = undefined,
    
    stdout: *std.Io.Writer = undefined,
    stderr: *std.Io.Writer = undefined,
    
    pub const Instance = struct {
        const Self = @This();
        const DA = std.heap.DebugAllocator(.{});
        const AA = std.heap.ArenaAllocator;
        const StdIO = struct {
            stdout_writer: std.Io.File.Writer = undefined,
            stderr_writer: std.Io.File.Writer = undefined,
            stdout_buffer: [4096]u8 = undefined,
            stderr_buffer: [4096]u8 = undefined,
            fn init(self: *@This(), io: std.Io) void {
                self.stdout_writer = std.Io.File.stdout().writer(io, &self.stdout_buffer);
                self.stderr_writer = std.Io.File.stderr().writer(io, &self.stderr_buffer);
            }
            fn deinit(self: *@This()) void {
                self.stdout_writer.interface.flush() catch {};
                self.stderr_writer.interface.flush() catch {};
            }
        };
    
        environ: std.process.Environ = std.process.Environ.empty,
        envmap: std.process.Environ.Map = undefined,
        log: Log = undefined,
        gpa: DA = undefined,
        aa: AA = undefined,
        io_threaded: std.Io.Threaded = undefined,
        io: std.Io = undefined,
        start_ts: std.Io.Timestamp = undefined,
        stdio: StdIO = undefined,
    
        pub fn init(self: *Self) void {
            self.gpa = DA{};
            const a = self.gpa.allocator();
            self.envmap = self.environ.createMap(a) catch std.process.Environ.Map.init(a);
            self.aa = AA.init(a);
            self.io_threaded = std.Io.Threaded.init(a, .{ .environ = self.environ });
            self.io = self.io_threaded.io();
            self.log = Log{ .io = self.io };
            self.log.init();
            self.start_ts = std.Io.Clock.now(.real, self.io);
            self.stdio.init(self.io);
        }
        pub fn deinit(self: *Self) void {
            self.stdio.deinit();
            self.log.deinit();
            self.io_threaded.deinit();
            self.aa.deinit();
            self.envmap.deinit();
            if (self.gpa.deinit() == .leak) {
                self.log.err("Found memory leaks in Env\n", .{}) catch {};
            }
        }
    
        pub fn env(self: *Self) Env_ {
            return .{
                .a = self.gpa.allocator(),
                .aa = self.aa.allocator(),
                .io = self.io,
                .envmap = &self.envmap,
                .log = &self.log,
                .stdout = &self.stdio.stdout_writer.interface,
                .stderr = &self.stdio.stderr_writer.interface,
            };
        }
    
        pub fn duration_ns(self: Self) i96 {
            const duration = self.start_ts.durationTo(std.Io.Clock.now(.real, self.io));
            return duration.nanoseconds;
        }
    };
    
    pub fn duration_ns(env: Env_) i96 {
        const inst: *const Instance = @alignCast(@fieldParentPtr("log", env.log));
        return inst.duration_ns();
    }
    
};

// Export from 'src/Log.zig'
pub const Log = struct {
    pub const Error = error{FilePathTooLong};
    
    // &improv: Support both buffered and non-buffered logging
    const Self = @This();
    
    const Autoclean = struct {
        buffer: [std.fs.max_path_bytes]u8 = undefined,
        filepath: []const u8 = &.{},
    };
    
    io: std.Io,
    
    _do_close: bool = false,
    _file: std.Io.File = undefined,
    
    _buffer: [1024]u8 = undefined,
    _writer: std.Io.File.Writer = undefined,
    
    _io: *std.Io.Writer = undefined,
    
    _lvl: usize = 0,
    
    _autoclean: ?Autoclean = null,
    
    pub fn init(self: *Self) void {
        self._file = std.Io.File.stdout();
        self.initWriter();
    }
    pub fn deinit(self: *Self) void {
        self.closeWriter() catch {};
        if (self._autoclean) |autoclean| {
            std.Io.Dir.deleteFileAbsolute(self.io, autoclean.filepath) catch {};
        }
    }
    
    // Any '%' in 'filepath' will be replaced with the process id
    const Options = struct {
        autoclean: bool = false,
    };
    pub fn toFile(self: *Self, filepath: []const u8, options: Options) !void {
        try self.closeWriter();
    
        var pct_count: usize = 0;
        for (filepath) |ch| {
            if (ch == '%')
                pct_count += 1;
        }
    
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const filepath_clean = if (pct_count > 0) blk: {
            var pid_buf: [32]u8 = undefined;
            const pid_str = try std.fmt.bufPrint(&pid_buf, "{}", .{std.c.getpid()});
            if (filepath.len + pct_count * pid_str.len >= buf.len)
                return Error.FilePathTooLong;
            var ix: usize = 0;
            for (filepath) |ch| {
                if (ch == '%') {
                    for (pid_str) |c| {
                        buf[ix] = c;
                        ix += 1;
                    }
                } else {
                    buf[ix] = ch;
                    ix += 1;
                }
            }
            break :blk buf[0..ix];
        } else blk: {
            break :blk filepath;
        };
    
        if (std.fs.path.isAbsolute(filepath_clean)) {
            self._file = try std.Io.Dir.createFileAbsolute(self.io, filepath_clean, .{});
            if (options.autoclean) {
                self._autoclean = undefined;
                const fp = self._autoclean.?.buffer[0..filepath_clean.len];
                std.mem.copyForwards(u8, fp, filepath_clean);
                if (self._autoclean) |*autoclean| {
                    autoclean.filepath = fp;
                }
            }
        } else {
            self._file = try std.Io.Dir.cwd().createFile(self.io, filepath_clean, .{});
        }
        self._do_close = true;
    
        self.initWriter();
    }
    
    pub fn setLevel(self: *Self, lvl: usize) void {
        self._lvl = lvl;
    }
    
    pub fn writer(self: Self) *std.Io.Writer {
        return self._io;
    }
    
    pub fn print(self: Self, comptime fmtstr: []const u8, args: anytype) !void {
        try self._io.print(fmtstr, args);
        try self._io.flush();
    }
    pub fn info(self: Self, comptime fmtstr: []const u8, args: anytype) !void {
        try self.print("Info: " ++ fmtstr, args);
    }
    pub fn warning(self: Self, comptime fmtstr: []const u8, args: anytype) !void {
        try self.print("Warning: " ++ fmtstr, args);
    }
    pub fn err(self: Self, comptime fmtstr: []const u8, args: anytype) !void {
        try self.print("Error: " ++ fmtstr, args);
    }
    
    pub fn level(self: Self, lvl: usize) ?*std.Io.Writer {
        if (self._lvl >= lvl)
            return self._io;
        return null;
    }
    
    fn initWriter(self: *Self) void {
        self._writer = self._file.writer(self.io, &self._buffer);
        self._io = &self._writer.interface;
    }
    fn closeWriter(self: *Self) !void {
        try self._io.flush();
        if (self._do_close) {
            self._file.close(self.io);
            self._do_close = false;
        }
    }
    
};

// Export from 'src/strng.zig'
pub const strng = struct {
    // &todo Support avoiding escaping with balanced brackets
    // &todo Implement escaping
    // &todo Support creating file/folder tree for UTs (mod+cli)
    // &todo Create spec
    // - Support for post-body attributes?
    
    pub const Strange = struct {
        const Self = @This();
    
        content: []const u8,
    
        pub fn empty(self: Self) bool {
            return self.content.len == 0;
        }
        pub fn size(self: Self) usize {
            return self.content.len;
        }
    
        pub fn str(self: Self) []const u8 {
            return self.content;
        }
    
        pub fn front(self: Self) ?u8 {
            if (self.content.len == 0)
                return null;
            return self.content[0];
        }
        pub fn back(self: Self) ?u8 {
            if (self.content.len == 0)
                return null;
            return self.content[self.content.len - 1];
        }
    
        pub fn popAll(self: *Self) ?[]const u8 {
            if (self.empty())
                return null;
            defer self.content = &.{};
            return self.content;
        }
    
        pub fn popMany(self: *Self, ch: u8) usize {
            for (self.content, 0..) |act, ix| {
                if (act != ch) {
                    self._popFront(ix);
                    return ix;
                }
            }
            defer self.content = &.{};
            return self.content.len;
        }
        pub fn popManyBack(self: *Self, ch: u8) usize {
            var count: usize = 0;
            while (self.content.len > 0 and self.content[self.content.len - 1] == ch) {
                self.content.len -= 1;
                count += 1;
            }
            return count;
        }
    
        pub fn popTo(self: *Self, ch: u8) ?[]const u8 {
            if (std.mem.indexOfScalar(u8, self.content, ch)) |ix| {
                defer self._popFront(ix + 1);
                return self.content[0..ix];
            } else {
                return null;
            }
        }
    
        pub fn popChar(self: *Self, ch: u8) bool {
            if (self.content.len > 0 and self.content[0] == ch) {
                self._popFront(1);
                return true;
            }
            return false;
        }
        pub fn popCharBack(self: *Self, ch: u8) bool {
            if (self.content.len > 0 and self.content[self.content.len - 1] == ch) {
                self._popBack(1);
                return true;
            }
            return false;
        }
    
        pub fn popOne(self: *Self) ?u8 {
            if (self.content.len > 0) {
                defer self._popFront(1);
                return self.content[0];
            }
            return null;
        }
    
        pub fn popStr(self: *Self, s: []const u8) bool {
            if (std.mem.startsWith(u8, self.content, s)) {
                self._popFront(s.len);
                return true;
            }
            return false;
        }
    
        pub fn popLine(self: *Self) ?[]const u8 {
            if (self.empty())
                return null;
    
            var line = self.content;
            if (std.mem.indexOfScalar(u8, self.content, '\n')) |ix| {
                line.len = if (ix > 0 and self.content[ix - 1] == '\r') ix - 1 else ix;
                self._popFront(ix + 1);
            } else {
                self.content = &.{};
            }
    
            return line;
        }
    
        pub fn popInt(self: *Self, T: type) ?T {
            // Find number of chars comprising number
            var slice = self.content;
            for (self.content, 0..) |ch, ix| {
                switch (ch) {
                    '0'...'9', '-', '+' => {},
                    else => {
                        slice.len = ix;
                        break;
                    },
                }
            }
            if (std.fmt.parseInt(T, slice, 10) catch null) |v| {
                self._popFront(slice.len);
                return v;
            }
            return null;
        }
    
        pub fn popIntMaxCount(self: *Self, T: type, max_count: usize) ?T {
            // Find number of chars comprising number
            const count = @min(max_count, self.content.len);
            var slice = self.content[0..count];
            for (slice, 0..) |ch, ix| {
                switch (ch) {
                    '0'...'9' => {},
                    '-', '+' => if (ix > 0) {
                        slice.len = ix;
                        break;
                    },
                    else => {
                        slice.len = ix;
                        break;
                    },
                }
            }
            if (std.fmt.parseInt(T, slice, 10) catch null) |v| {
                self._popFront(slice.len);
                return v;
            }
            return null;
        }
    
        pub fn popFront(self: *Self, count: usize) ?[]const u8 {
            if (self.content.len < count)
                return null;
            defer self._popFront(count);
            return self.content[0..count];
        }
    
        fn _popFront(self: *Self, count: usize) void {
            self.content.ptr += count;
            self.content.len -= count;
        }
        fn _popBack(self: *Self, count: usize) void {
            self.content.len -= count;
        }
    };
    
};

// Export from 'src/strings.zig'
pub const strings = struct {
    const ut = std.testing;
    
    pub const Strings = std.ArrayList([]const u8);
    
    pub fn index(comptime T: type, haystack: []const []const T, needle: []const T) ?usize {
        for (haystack, 0..) |el, ix| {
            if (std.mem.eql(T, needle, el))
                return ix;
        }
        return null;
    }
    
    pub fn contains(comptime T: type, haystack: []const []const T, needle: []const T) bool {
        return index(T, haystack, needle) != null;
    }
    
};

// Export from 'src/naft.zig'
pub const naft = struct {
    const Error = error{
        CouldNotCreateStdOut,
    };
    
    pub const Node = struct {
        const Self = @This();
    
        w: ?*std.Io.Writer,
    
        level: usize = 0,
        // Indicates if this Node already contains nested elements (Text, Node). This is used to add a closing '}' upon deinit().
        has_block: bool = false,
        // Indicates if this Node already contains a Node. This is used for deciding newlines etc.
        has_node: bool = false,
    
        pub fn root(w: ?*std.Io.Writer) Node {
            return .{ .w = w, .has_block = true };
        }
        pub fn deinit(self: Self) void {
            if (self.level == 0)
                // The top-level block does not need any handling
                return;
    
            if (self.has_block) {
                if (self.has_node)
                    self.indent();
                self.print("}}\n", .{});
            } else {
                self.print("\n", .{});
            }
        }
    
        pub fn node(self: *Self, name: []const u8) Node {
            self.ensure_block(true);
            const n = Node{ .w = self.w, .level = self.level + 1 };
            n.indent();
            n.print("[{s}]", .{name});
            return n;
        }
        pub fn node2(self: *Self, name: []const u8, name2: []const u8) Node {
            self.ensure_block(true);
            const n = Node{ .w = self.w, .level = self.level + 1 };
            n.indent();
            n.print("[{s}:{s}]", .{ name, name2 });
            return n;
        }
    
        pub fn attr(self: *Self, key: []const u8, value: anytype) void {
            const T = @TypeOf(value);
    
            if (self.has_block) {
                std.debug.print("Attributes are not allowed anymore: block was already started\n", .{});
                return;
            }
    
            const str = switch (@typeInfo(T)) {
                // We assume that any .pointer can be printed as a string
                .pointer => "s",
                .@"struct" => if (@hasDecl(T, "format")) "f" else "any",
                else => "any",
            };
    
            self.print("({s}:{" ++ str ++ "})", .{ key, value });
        }
        pub fn attr1(self: *Self, value: anytype) void {
            if (self.has_block) {
                std.debug.print("Attributes are not allowed anymore: block was already started\n", .{});
                return;
            }
    
            const str = switch (@typeInfo(@TypeOf(value))) {
                // We assume that any .pointer can be printed as a string
                .pointer => "s",
                else => "any",
            };
    
            self.print("({" ++ str ++ "})", .{value});
        }
    
        pub fn text(self: *Self, str: []const u8) void {
            self.ensure_block(false);
            self.print("{s}", .{str});
        }
    
        fn ensure_block(self: *Self, is_node: bool) void {
            if (!self.has_block)
                self.print("{{", .{});
            self.has_block = true;
            if (is_node) {
                if (!self.has_node)
                    self.print("\n", .{});
                self.has_node = is_node;
            }
        }
    
        fn indent(self: Self) void {
            if (self.level > 1)
                for (0..self.level - 1) |_|
                    self.print("  ", .{});
        }
    
        fn print(self: Self, comptime fmtstr: []const u8, args: anytype) void {
            if (self.w) |io| {
                io.print(fmtstr, args) catch {};
                io.flush() catch {};
            } else {
                std.debug.print(fmtstr, args);
            }
        }
    };
    
};

// Export from 'src/walker.zig'
pub const walker = struct {
    // &todo Take `.gitignore` and `.ignore` into account
    
    pub const Offsets = struct {
        base: usize = 0,
        name: usize = 0,
    };
    
    pub const Kind = enum {
        Enter,
        Leave,
        File,
    };
    
    pub const Walker = struct {
        const Ignore = struct { buffer: Buffer = undefined, ignore: ignore.Ignore = undefined, path_len: usize = 0 };
        const IgnoreStack = std.ArrayList(Ignore);
        const Buffer = std.ArrayList(u8);
    
        env: Env,
    
        filter: Filter = .{},
    
        // We keep track of the current path as a []const u8. If the caller has to do this,
        // he has to use Dir.realPath() which is less efficient.
        buffer: [std.fs.max_path_bytes]u8 = undefined,
        path: []const u8 = &.{},
        base: usize = undefined,
    
        ignore_offset: usize = 0,
    
        ignore_stack: IgnoreStack = .empty,
    
        pub fn deinit(self: *Walker) void {
            for (self.ignore_stack.items) |*item| {
                item.ignore.deinit();
                item.buffer.deinit(self.env.a);
            }
            self.ignore_stack.deinit(self.env.a);
        }
    
        // cb() is passed:
        // - dir: std.Io.Dir
        // - path: full path of file/folder
        // - offsets: optional offsets for basename and filename. Only for the toplevel Enter/Leave is this null to avoid out of bound reading
        // - kind: Enter/Leave/File
        pub fn walk(self: *Walker, basedir: std.Io.Dir, cb: anytype) !void {
            const len = try basedir.realPathFile(self.env.io, ".", &self.buffer);
            self.path = self.buffer[0..len];
            self.base = self.path.len + 1;
    
            var dir = try basedir.openDir(self.env.io, ".", .{ .iterate = true });
            defer dir.close(self.env.io);
    
            const path = self.path;
    
            try cb.call(dir, path, null, Kind.Enter);
            try self._walk(dir, cb);
            try cb.call(dir, path, null, Kind.Leave);
        }
    
        fn _walk(self: *Walker, dir: std.Io.Dir, cb: anytype) !void {
            var added_ignore = false;
    
            if (dir.openFile(self.env.io, ".gitignore", .{})) |file| {
                defer file.close(self.env.io);
    
                const stat = try file.stat(self.env.io);
    
                var ig = Ignore{ .buffer = try Buffer.initCapacity(self.env.a, stat.size) };
                try ig.buffer.resize(self.env.a, stat.size);
                var buf: [1024]u8 = undefined;
                var reader = file.reader(self.env.io, &buf);
                try reader.interface.readSliceAll(ig.buffer.items);
    
                ig.ignore = try ignore.Ignore.initFromContent(ig.buffer.items, self.env.a);
                ig.path_len = self.path.len;
                try self.ignore_stack.append(self.env.a, ig);
    
                self.ignore_offset = ig.path_len + 1;
    
                added_ignore = true;
            } else |_| {}
    
            var it = dir.iterate();
            while (try it.next(self.env.io)) |el| {
                if (!self.filter.call(dir, el))
                    continue;
    
                const orig_path_len = self.path.len;
                defer self.path.len = orig_path_len;
    
                const offsets = Offsets{ .base = self.base, .name = self.path.len + 1 };
                self._append_to_path(el.name);
    
                switch (el.kind) {
                    std.Io.File.Kind.file => {
                        if (slc.last(self.ignore_stack.items)) |e| {
                            const ignore_path = self.path[self.ignore_offset..];
                            if (e.ignore.match(ignore_path))
                                continue;
                        }
    
                        try cb.call(dir, self.path, offsets, Kind.File);
                    },
                    std.Io.File.Kind.directory => {
                        if (slc.last(self.ignore_stack.items)) |e| {
                            const ignore_path = self.path[self.ignore_offset..];
                            if (e.ignore.match(ignore_path))
                                continue;
                        }
    
                        var subdir = try dir.openDir(self.env.io, el.name, .{ .iterate = true });
                        defer subdir.close(self.env.io);
    
                        const path = self.path;
    
                        try cb.call(subdir, path, offsets, Kind.Enter);
    
                        try self._walk(subdir, cb);
    
                        try cb.call(subdir, path, offsets, Kind.Leave);
                    },
                    else => {},
                }
            }
    
            if (added_ignore) {
                if (self.ignore_stack.pop()) |v| {
                    var v_mut = v;
                    v_mut.buffer.deinit(self.env.a);
                    v_mut.ignore.deinit();
                }
    
                self.ignore_offset = if (slc.last(self.ignore_stack.items)) |x| x.path_len + 1 else 0;
            }
        }
    
        fn _append_to_path(self: *Walker, name: []const u8) void {
            self.buffer[self.path.len] = '/';
            self.path.len += 1;
    
            std.mem.copyForwards(u8, self.buffer[self.path.len..], name);
            self.path.len += name.len;
        }
    };
    
    pub const Filter = struct {
        // Skip hidden files by default
        hidden: bool = true,
    
        // Skip files with following extensions. Include '.' in extension.
        extensions: []const []const u8 = &.{},
    
        fn call(self: Filter, _: std.Io.Dir, entry: std.Io.Dir.Entry) bool {
            if (self.hidden and is_hidden(entry.name))
                return false;
    
            const my_ext = std.fs.path.extension(entry.name);
            for (self.extensions) |ext| {
                if (std.mem.eql(u8, my_ext, ext))
                    return false;
            }
    
            return true;
        }
    };
    
    fn is_hidden(name: []const u8) bool {
        return name.len > 0 and name[0] == '.';
    }
    

    // Export from 'src/walker/ignore.zig'
    pub const ignore = struct {
        pub const Ignore = struct {
            const Self = @This();
            const Globs = std.ArrayList(glb.Glob);
            const Strings = std.ArrayList([]const u8);
        
            a: std.mem.Allocator,
            globs: Globs = .empty,
            antiglobs: Globs = .empty,
        
            pub fn init(a: std.mem.Allocator) Ignore {
                return Ignore{ .a = a };
            }
        
            pub fn deinit(self: *Self) void {
                for ([_]*Globs{ &self.globs, &self.antiglobs }) |globs| {
                    for (globs.items) |*item|
                        item.deinit();
                    globs.deinit(self.a);
                }
            }
        
            pub fn initFromFile(dir: std.Io.Dir, name: []const u8, a: std.mem.Allocator) !Self {
                const file = try dir.openFile(name, .{});
                defer file.close();
        
                const stat = try file.stat();
        
                const r = file.reader();
        
                const content = try r.readAllAlloc(a, stat.size);
                defer a.free(content);
        
                return initFromContent(content, a);
            }
        
            pub fn initFromContent(content: []const u8, a: std.mem.Allocator) !Self {
                var self = Self.init(a);
                errdefer self.deinit();
        
                var strange_content = strng.Strange{ .content = content };
                while (strange_content.popLine()) |line| {
                    var strange_line = strng.Strange{ .content = line };
        
                    // Trim
                    _ = strange_line.popMany(' ');
                    _ = strange_line.popManyBack(' ');
        
                    if (strange_line.popMany('#') > 0)
                        // Skip comments
                        continue;
        
                    if (strange_line.empty())
                        continue;
        
                    const is_anti = strange_line.popMany('!') > 0;
                    const globs = if (is_anti) &self.antiglobs else &self.globs;
        
                    // '*.txt'    ignores '**/*.txt'
                    // 'dir/'     ignores '**/dir/**'
                    // '/dir/'    ignores 'dir/**'
                    // 'test.txt' ignores '**/test.txt'
                    var config = glb.Config{};
                    if (strange_line.popMany('/') == 0)
                        config.front = "**";
                    config.pattern = strange_line.str();
                    if (strange_line.back() == '/')
                        config.back = "**";
        
                    try globs.append(a, try glb.Glob.init(config, a));
                }
        
                return self;
            }
        
            pub fn addExt(self: *Ignore, ext: []const u8) !void {
                const buffer: [128]u8 = undefined;
                const fba = std.heap.FixedBufferAllocator.init(buffer);
                const my_ext = try std.mem.concat(fba, u8, &[_][]const u8{ ".", ext });
        
                const glob_config = glb.Config{ .pattern = my_ext, .front = "**" };
                try self.globs.append(self.a, try glb.Glob.init(glob_config, self.globs.allocator));
            }
        
            pub fn match(self: Self, fp: []const u8) bool {
                var ret = false;
                for (self.globs.items) |item| {
                    if (item.match(fp))
                        ret = true;
                }
                for (self.antiglobs.items) |item| {
                    if (item.match(fp))
                        ret = false;
                }
                return ret;
            }
        };
        
    };
};

// Export from 'src/slc.zig'
pub const slc = struct {
    pub fn isEmpty(slice: anytype) bool {
        return slice.len == 0;
    }
    
    pub fn first(slice: anytype) ?@TypeOf(slice[0]) {
        return if (slice.len > 0) slice[0] else null;
    }
    pub fn firstPtr(slice: anytype) ?@TypeOf(&slice[0]) {
        return if (slice.len > 0) &slice[0] else null;
    }
    pub fn firstPtrUnsafe(slice: anytype) @TypeOf(&slice[0]) {
        return &slice[0];
    }
    
    pub fn last(slice: anytype) ?@TypeOf(slice[0]) {
        return if (slice.len > 0) slice[slice.len - 1] else null;
    }
    pub fn lastPtr(slice: anytype) ?@TypeOf(&slice[0]) {
        return if (slice.len > 0) &slice[slice.len - 1] else null;
    }
    pub fn lastPtrUnsafe(slice: anytype) @TypeOf(&slice[0]) {
        return &slice[slice.len - 1];
    }
    
};

// Export from 'src/glb.zig'
pub const glb = struct {
    // &todo Support '?' pattern
    
    const Error = error{
        EmptyPattern,
        IllegalWildcard,
    };
    
    const Wildcard = enum {
        None,
        Some, // '*': All characters except path separator '/'
        All, // '**': All characters
    
        pub fn fromStr(str: []const u8) !Wildcard {
            if (str.len == 0)
                return Wildcard.None;
            if (std.mem.eql(u8, str, "*"))
                return Wildcard.Some;
            if (std.mem.eql(u8, str, "**"))
                return Wildcard.All;
            return Error.IllegalWildcard;
        }
    
        pub fn max(a: Wildcard, b: Wildcard) Wildcard {
            return switch (a) {
                Wildcard.None => b,
                Wildcard.Some => if (b == Wildcard.None) a else b,
                Wildcard.All => a,
            };
        }
    };
    
    // A Part is easy to match: search for str and check if whatever in-between matches with wildcard
    const Part = struct {
        wildcard: Wildcard,
        str: []const u8,
    };
    
    pub const Config = struct {
        pattern: []const u8 = &.{},
        front: []const u8 = &.{},
        back: []const u8 = &.{},
    };
    
    pub const Glob = struct {
        const Self = @This();
        const Parts = std.ArrayList(Part);
    
        a: std.mem.Allocator,
        parts: Parts = .empty,
        config: ?*Config = null,
    
        pub fn init(config: Config, ma: std.mem.Allocator) !Glob {
            // Create our own copy of config to unsure it outlives self
            const my_config = try ma.create(Config);
            my_config.pattern = try ma.dupe(u8, config.pattern);
            my_config.front = try ma.dupe(u8, config.front);
            my_config.back = try ma.dupe(u8, config.back);
    
            var ret = try initUnmanaged(my_config.*, ma);
            ret.config = my_config;
    
            return ret;
        }
    
        // Assumes config outlives self
        pub fn initUnmanaged(config: Config, a: std.mem.Allocator) !Glob {
            if (config.pattern.len == 0)
                return Error.EmptyPattern;
    
            var glob = Glob{ .a = a };
    
            var strange = strng.Strange{ .content = config.pattern };
    
            var wildcard = try Wildcard.fromStr(config.front);
    
            while (true) {
                if (strange.popTo('*')) |str| {
                    if (str.len > 0) {
                        try glob.parts.append(a, Part{ .wildcard = wildcard, .str = str });
                    }
    
                    // We found a single '*', check for more '*' to decide if we can match path separators as well
                    {
                        const new_wildcard = if (strange.popMany('*') > 0) Wildcard.All else Wildcard.Some;
    
                        if (str.len == 0) {
                            // When pattern starts with a '*', keep the config.front wildcard if it is stronger
                            wildcard = Wildcard.max(wildcard, new_wildcard);
                        } else {
                            wildcard = new_wildcard;
                        }
                    }
    
                    if (strange.empty()) {
                        // We popped everything from strange and will hence not enter below's branch: setup wildcard according to config.back
                        const new_wildcard = try Wildcard.fromStr(config.back);
                        wildcard = Wildcard.max(wildcard, new_wildcard);
                    }
                } else if (strange.popAll()) |str| {
                    try glob.parts.append(a, Part{ .wildcard = wildcard, .str = str });
    
                    wildcard = try Wildcard.fromStr(config.back);
                } else {
                    try glob.parts.append(a, Part{ .wildcard = wildcard, .str = "" });
                    break;
                }
            }
    
            return glob;
        }
    
        pub fn deinit(self: *Self) void {
            self.parts.deinit(self.a);
            if (self.config) |el| {
                self.a.free(el.pattern);
                self.a.free(el.front);
                self.a.free(el.back);
                self.a.destroy(el);
            }
        }
    
        pub fn match(self: Self, haystack: []const u8) bool {
            return _match(self.parts.items, haystack);
        }
    
        fn _match(parts: []const Part, haystack: []const u8) bool {
            if (parts.len == 0)
                return true;
    
            const part = &parts[0];
    
            switch (part.wildcard) {
                Wildcard.None => {
                    if (part.str.len == 0) {
                        // This is a special case with an empty part.str: this should only for the last part
                        std.debug.assert(parts.len == 1);
    
                        // None only matches if we are at the end
                        return haystack.len == 0;
                    }
    
                    if (!std.mem.startsWith(u8, haystack, part.str))
                        return false;
    
                    return _match(parts[1..], haystack[part.str.len..]);
                },
                Wildcard.Some => {
                    if (part.str.len == 0) {
                        // This is a special case with an empty part.str: this should only for the last part
                        std.debug.assert(parts.len == 1);
    
                        // Accept a full match if there is no path separator
                        return std.mem.indexOfScalar(u8, haystack, '/') == null;
                    } else {
                        var start: usize = 0;
                        while (start < haystack.len) {
                            if (std.mem.indexOf(u8, haystack[start..], part.str)) |ix| {
                                if (std.mem.indexOfScalar(u8, haystack[start .. start + ix], '/')) |_|
                                    // We found a path separator: this is not a match
                                    return false;
                                if (_match(parts[1..], haystack[start + ix + part.str.len ..]))
                                    // We found a match for the other parts
                                    return true;
                                // No match found downstream: try to match part.str further in haystack
                                start += ix + 1;
                            }
                            break;
                        }
                    }
                    return false;
                },
                Wildcard.All => {
                    if (part.str.len == 0) {
                        // This is a special case with an empty part.str: this should only be used for the last part
                        std.debug.assert(parts.len == 1);
    
                        // Accept a full match until the end if this is the last part.
                        // If this is not the last part, something unexpected happened: Glob.init() should not produce something like that
                        return parts.len == 1;
                    } else {
                        var start: usize = 0;
                        while (start < haystack.len) {
                            if (std.mem.indexOf(u8, haystack[start..], part.str)) |ix| {
                                if (_match(parts[1..], haystack[start + ix + part.str.len ..]))
                                    // We found a match for the other parts
                                    return true;
                                // No match found downstream: try to match part.str further in haystack
                                start += ix + 1;
                            }
                            break;
                        }
                    }
                    return false;
                },
            }
        }
    };
    
};

// Export from 'src/idx.zig'
pub const idx = struct {
    pub const Range = struct {
        const Self = @This();
    
        begin: usize = 0,
        end: usize = 0,
    
        pub fn empty(self: Self) bool {
            return self.begin == self.end;
        }
        pub fn size(self: Self) usize {
            return self.end - self.begin;
        }
    
        pub fn write(self: Self, parent: *naft.Node, name: []const u8) void {
            var n = parent.node2("idx.Range", name);
            defer n.deinit();
            n.attr("begin", self.begin);
            n.attr("end", self.end);
        }
    };
    
    // Type-safe index to work with 'pointers into a slice'
    pub fn Ix(T: type) type {
        return struct {
            const Self = @This();
    
            ix: usize = 0,
    
            pub fn init(ix: usize) Self {
                return Self{ .ix = ix };
            }
    
            pub fn eql(self: Self, rhs: Self) bool {
                return self.ix == rhs.ix;
            }
    
            pub fn get(self: Self, slice: []T) ?*T {
                if (self.ix >= slice.len)
                    return null;
                return &slice[self.ix];
            }
            pub fn cget(self: Self, slice: []const T) ?*const T {
                if (self.ix >= slice.len)
                    return null;
                return &slice[self.ix];
            }
    
            // Unchecked version of get()
            pub fn ptr(self: Self, slice: []T) *T {
                return &slice[self.ix];
            }
            pub fn cptr(self: Self, slice: []const T) *const T {
                return &slice[self.ix];
            }
    
            pub fn format(self: Self, io: *std.Io.Writer) !void {
                try io.print("{}", .{self.ix});
            }
        };
    }
    
};

// Export from 'src/cli.zig'
pub const cli = struct {
    // Allocates everything on env.aa: no need for deinit() or lifetime management
    pub const Args = struct {
        const Self = @This();
    
        env: Env,
        argv: [][]const u8 = &.{},
    
        pub fn setupFromOS(self: *Self, os_args: std.process.Args) !void {
            const a = self.env.aa;
    
            self.argv = try a.alloc([]const u8, os_args.vector.len);
    
            var it = os_args.iterate();
            var ix: usize = 0;
            while (it.next()) |os_arg| {
                self.argv[ix] = try a.dupe(u8, os_arg);
                ix += 1;
            }
        }
        pub fn setupFromData(self: *Self, argv: []const []const u8) !void {
            const a = self.env.aa;
    
            self.argv = try a.alloc([]const u8, argv.len);
            for (argv, 0..) |slice, ix| {
                self.argv[ix] = try a.dupe(u8, slice);
            }
        }
    
        pub fn pop(self: *Self) ?Arg {
            if (self.argv.len == 0) return null;
    
            const a = self.env.aa;
            const arg = a.dupe(u8, std.mem.sliceTo(self.argv[0], 0)) catch return null;
            self.argv.ptr += 1;
            self.argv.len -= 1;
    
            return Arg{ .arg = arg };
        }
    };
    
    pub const Arg = struct {
        const Self = @This();
    
        arg: []const u8,
    
        pub fn is(self: Arg, sh: []const u8, lh: []const u8) bool {
            return std.mem.eql(u8, self.arg, sh) or std.mem.eql(u8, self.arg, lh);
        }
    
        pub fn as(self: Self, T: type) !T {
            return try std.fmt.parseInt(T, self.arg, 10);
        }
    };
    
};

// Export from 'src/datex.zig'
pub const datex = struct {
    const SYSTEMTIME = extern struct {
        wYear: u16,
        wMonth: u16,
        wDayOfWeek: u16,
        wDay: u16,
        wHour: u16,
        wMinute: u16,
        wSecond: u16,
        wMilliseconds: u16,
    };
    // You can call any Win32 API directly via `extern` + `callconv(.winapi)`. :contentReference[oaicite:1]{index=1}
    extern "kernel32" fn GetLocalTime(lpSystemTime: *SYSTEMTIME) callconv(.winapi) void;
    extern "kernel32" fn GetSystemTime(lpSystemTime: *SYSTEMTIME) callconv(.winapi) void;
    
    pub const Date = struct {
        const Self = @This();
    
        epoch_day: std.time.epoch.EpochDay,
    
        pub fn today(io: std.Io) !Date {
            if (builtin.os.tag == .windows) {
                var st: SYSTEMTIME = undefined;
                GetLocalTime(&st);
    
                var day: u47 = 0;
                {
                    var year: u16 = 1970;
                    for (1970..st.wYear) |y| {
                        year = @intCast(y);
                        day += std.time.epoch.getDaysInYear(year);
                    }
                    for (1..st.wMonth) |m| {
                        day += std.time.epoch.getDaysInMonth(year, @enumFromInt(m));
                    }
                    day += st.wDay - 1;
                }
    
                return .{ .epoch_day = .{ .day = day } };
            } else {
                // const time = try std.posix.clock_gettime(.REALTIME);
                // const secs = time.sec;
                const secs = std.Io.Clock.now(.real, io).toSeconds();
                const esecs = std.time.epoch.EpochSeconds{ .secs = @intCast(secs) };
                return .{ .epoch_day = esecs.getEpochDay() };
            }
        }
    
        pub fn fromEpochDays(days: u47) Date {
            return Date{ .epoch_day = std.time.epoch.EpochDay{ .day = days } };
        }
    
        pub fn yearDay(self: Self) std.time.epoch.YearAndDay {
            return self.epoch_day.calculateYearDay();
        }
    
        pub fn format(self: Self, w: *std.Io.Writer) !void {
            const yd = self.epoch_day.calculateYearDay();
            const md = yd.calculateMonthDay();
            try w.print("{:04}{:02}{:02}", .{ yd.year, md.month.numeric(), md.day_index + 1 });
        }
    };
    
};

// Export from 'src/tree.zig'
pub const tree = struct {
    pub const Error = error{
        UnknownNode,
    };
    
    pub fn Tree(Data: type) type {
        return struct {
            const Self = @This();
            pub const Id = usize;
            pub const Ids = std.ArrayList(usize);
    
            pub const Entry = struct {
                id: usize,
                data: *Data,
            };
    
            const Node = struct {
                data: Data,
                child_ids: Ids,
                parent_id: ?Id = null,
            };
            const Nodes = std.ArrayList(Node);
    
            a: std.mem.Allocator,
            nodes: Nodes = .empty,
            root_ids: Ids = .empty,
    
            pub fn init(a: std.mem.Allocator) Self {
                return Self{ .a = a };
            }
            pub fn deinit(self: *Self) void {
                for (self.nodes.items) |*node|
                    node.child_ids.deinit(self.a);
                self.nodes.deinit(self.a);
                self.root_ids.deinit(self.a);
            }
    
            pub fn get(self: *Self, id: Id) !*Data {
                if (id >= self.nodes.items.len)
                    return Error.UnknownNode;
                return &self.nodes.items[id].data;
            }
            pub fn cget(self: Self, id: Id) !*const Data {
                if (id >= self.nodes.items.len)
                    return Error.UnknownNode;
                return &self.nodes.items[id].data;
            }
    
            pub fn ptr(self: *Self, id: Id) *Data {
                return &self.nodes.items[id].data;
            }
            pub fn cptr(self: Self, id: Id) *const Data {
                return &self.nodes.items[id].data;
            }
    
            pub fn parent(self: Self, id: Id) !?Entry {
                if (id >= self.nodes.items.len)
                    return Error.UnknownNode;
                if (self.nodes.items[id].parent_id) |pid|
                    return Entry{ .id = pid, .data = &self.nodes.items[pid].data };
                return null;
            }
    
            pub fn childIds(self: Self, parent_id: Id) []const Id {
                return self.nodes.items[parent_id].child_ids.items;
            }
            pub fn childIdsMut(self: *Self, parent_id: Id) []Id {
                return self.nodes.items[parent_id].child_ids.items;
            }
    
            pub fn addChild(self: *Self, maybe_parent_id: ?Id) !Entry {
                var ids: *Ids = undefined;
                if (maybe_parent_id) |parent_id| {
                    if (parent_id >= self.nodes.items.len)
                        return Error.UnknownNode;
                    ids = &self.nodes.items[parent_id].child_ids;
                } else {
                    ids = &self.root_ids;
                }
    
                const child_id = self.nodes.items.len;
                try ids.append(self.a, child_id);
    
                const child = try self.nodes.addOne(self.a);
                child.child_ids = Ids.empty;
                child.parent_id = maybe_parent_id;
    
                return Entry{ .id = child_id, .data = &child.data };
            }
    
            pub fn depth(self: Self, id: Id) !usize {
                if (id >= self.nodes.items.len)
                    return Error.UnknownNode;
                var d: usize = 0;
                var id_ = id;
                while (true) {
                    if (self.nodes.items[id_].parent_id) |pid| {
                        d += 1;
                        id_ = pid;
                    } else break;
                }
                return d;
            }
    
            pub fn dfsAll(self: *Self, cb: anytype) CallbackErrorSet(@TypeOf(cb.*))!void {
                for (self.root_ids.items) |root_id| {
                    try self.dfs(root_id, cb);
                }
            }
            pub fn dfs(self: *Self, id: Id, cb: anytype) CallbackErrorSet(@TypeOf(cb.*))!void {
                const n = &self.nodes.items[id];
                const entry = Entry{ .id = id, .data = &n.data };
                try cb.call(entry, true);
                for (n.child_ids.items) |child_id|
                    try self.dfs(child_id, cb);
                try cb.call(entry, false);
            }
    
            pub fn each(self: *Self, cb: anytype) CallbackErrorSet(@TypeOf(cb.*))!void {
                for (self.nodes.items, 0..) |*node, id|
                    try cb.call(Entry{ .id = id, .data = &node.data });
            }
    
            pub fn toRoot(self: *Self, id: Id, cb: anytype) void {
                var entry = Entry{ .id = id, .data = self.get(id) catch return };
                cb.call(&entry);
    
                while (self.parent(entry.id) catch return) |pentry| {
                    entry = pentry;
                    cb.call(&entry);
                }
            }
        };
    }
    
    // When a callback calls some Tree func itself, Zig cannot infer the ErrorSet
    // With below comptime machinery, we can express that a certain Tree func has
    // the same ErrorSet as the Callback
    fn CallbackErrorSet(Callback: type) type {
        const fn_info = @typeInfo(@TypeOf(Callback.call)).@"fn";
        const rt = fn_info.return_type orelse
            @compileError("Callback.call() must have a return value");
    
        const rt_info = @typeInfo(rt);
        if (rt_info != .error_union)
            @compileError("Callback.call() must return an error union");
    
        return rt_info.error_union.error_set;
    }
    
};

// Export from 'src/lsp.zig'
pub const lsp = struct {
    pub const Error = error{
        UnexpectedKey,
        CouldNotReadEOH,
        CouldNotReadContentLength,
        UnexpectedCountForOptional,
        ExpectedValidRequest,
        ExpectedValidId,
    };
    
    pub const Server = struct {
        const Self = @This();
        const Buffer = std.ArrayList(u8);
    
        in: *std.Io.Reader,
        out: *std.Io.Writer,
        log: ?*std.Io.Writer,
        a: std.mem.Allocator,
    
        content_length: ?usize = null,
        content: Buffer = .empty,
    
        aa: std.heap.ArenaAllocator,
        request: ?dto.Request = null,
    
        pub fn init(in: *std.Io.Reader, out: *std.Io.Writer, log: ?*std.Io.Writer, a: std.mem.Allocator) Self {
            return Self{
                .in = in,
                .out = out,
                .log = log,
                .a = a,
                .aa = std.heap.ArenaAllocator.init(a),
            };
        }
        pub fn deinit(self: *Self) void {
            self.content.deinit(self.a);
            self.aa.deinit();
        }
    
        pub fn receive(self: *Self) !*const dto.Request {
            self.aa.deinit();
            self.aa = std.heap.ArenaAllocator.init(self.a);
    
            try self.readHeader();
            try self.readContent();
    
            if (self.log) |log| {
                try log.print("[Request]({s})\n", .{self.content.items});
                try log.flush();
            }
            self.request = (try std.json.parseFromSlice(dto.Request, self.aa.allocator(), self.content.items, .{})).value;
    
            return &(self.request orelse unreachable);
        }
    
        pub fn send(self: *Self, result: anytype) !void {
            const request = self.request orelse return Error.ExpectedValidRequest;
            const id = request.id orelse return Error.ExpectedValidId;
            defer self.request = null;
    
            const Result = @TypeOf(result);
    
            const response = sw: switch (@typeInfo(Result)) {
                .null => {
                    const Response = dto.Response(bool);
                    break :sw Response{ .id = id, .result = null };
                },
                else => {
                    const Response = dto.Response(Result);
                    break :sw Response{ .id = id, .result = &result };
                },
            };
    
            try self.content.resize(self.a, 0);
    
            var acc = std.Io.Writer.Allocating.fromArrayList(self.a, &self.content);
            defer acc.deinit();
    
            try std.json.Stringify.value(response, .{}, &acc.writer);
    
            self.content = acc.toArrayList();
    
            if (self.log) |log| {
                try log.print("[Response]({s})\n", .{self.content.items});
                try log.flush();
            }
    
            try self.out.print("Content-Length: {}\r\n\r\n{s}", .{ self.content.items.len, self.content.items });
            try self.out.flush();
        }
    
        fn readHeader(self: *Self) !void {
            self.content_length = null;
    
            var buffer: [1024]u8 = undefined;
            var w = std.Io.Writer.fixed(&buffer);
    
            const size = try self.in.streamDelimiter(&w, '\r');
    
            const line = buffer[0..size];
            if (self.log) |log| {
                try log.print("[Line](size:{})(content:{s})\n", .{ size, line });
                try log.flush();
            }
    
            var str = strng.Strange{ .content = line };
    
            if (str.popStr("Content-Length:")) {
                _ = str.popMany(' ');
                self.content_length = str.popInt(usize) orelse return Error.CouldNotReadContentLength;
            } else return Error.UnexpectedKey;
    
            // Read the remaining "\r\n\r\n"
            const slice = buffer[0..4];
            try self.in.readSliceAll(slice);
            if (!std.mem.eql(u8, slice, "\r\n\r\n")) return Error.CouldNotReadEOH;
        }
    
        fn readContent(self: *Self) !void {
            if (self.content_length) |cl| {
                try self.content.resize(self.a, cl);
                try self.in.readSliceAll(self.content.items);
            }
        }
    };
    
    pub const Client = struct {
        const Self = @This();
        const Buffer = std.ArrayList(u8);
    
        in: std.Io.File.Reader,
        out: *std.Io.Writer,
        log: ?*std.Io.Writer,
        a: std.mem.Allocator,
    
        content_length: ?usize = null,
        content: Buffer,
    
        aa: std.heap.ArenaAllocator,
        request: ?dto.Request = null,
    
        res_initialize: dto.Response(dto.InitializeResult) = undefined,
    
        pub fn init(in: std.Io.File.Reader, out: *std.Io.Writer, log: ?*std.Io.Writer, a: std.mem.Allocator) Self {
            return Self{
                .in = in,
                .out = out,
                .log = log,
                .a = a,
                .content = Buffer.init(a),
                .aa = std.heap.ArenaAllocator.init(a),
            };
        }
        pub fn deinit(self: *Self) void {
            self.content.deinit();
            self.aa.deinit();
        }
    
        pub fn send(self: *Self, request: dto.Request) !void {
            try self.content.resize(0);
            try std.json.stringify(request, .{}, self.content.writer());
            if (self.log) |log| {
                try log.print("[Request]({s})\n", .{self.content.items});
                try log.flush();
            }
    
            try self.out.print("Content-Length: {}\r\n\r\n{s}", .{ self.content.items.len, self.content.items });
            try self.out.flush();
        }
    
        pub fn receive(self: *Self, T: type) !*const T {
            self.aa.deinit();
            self.aa = std.heap.ArenaAllocator.init(self.a);
    
            try self.readHeader();
            try self.readContent();
    
            if (self.log) |log| {
                try log.print("[Response]({s})\n", .{self.content.items});
                try log.flush();
            }
    
            const resp = self.response_(T);
            resp.* = (try std.json.parseFromSlice(T, self.aa.allocator(), self.content.items, .{})).value;
    
            return resp;
        }
    
        fn response_(self: *Self, T: type) *T {
            if (dto.Response(T) == @TypeOf(self.res_initialize)) {
                return &self.res_initialize;
            }
            unreachable;
        }
    };
    

    // Export from 'src/lsp/dto.zig'
    pub const dto = struct {
        // Data Transfer Objects for LSP
        // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#responseMessage
        
        pub const String = []const u8;
        
        pub const Request = struct {
            pub const Params = struct {
                capabilities: ?ClientCapabilities = null,
                clientInfo: ?ClientInfo = null,
                processId: ?usize = null,
                rootPath: ?String = null,
                rootUri: ?String = null,
                workspaceFolders: ?[]WorkspaceFolder = null,
                textDocument: ?TextDocumentItem = null,
                query: ?String = null,
                contentChanges: ?[]ContentChange = null,
                position: ?Position = null,
                context: ?ReferenceContext = null,
                range: ?Range = null,
                command: ?String = null,
                arguments: ?[]const String = null,
                event: ?Event = null,
            };
        
            jsonrpc: String,
            method: String,
            params: ?Params = null,
            id: ?i32 = null,
        
            pub fn is(self: Request, method: String) bool {
                return std.mem.eql(u8, method, self.method);
            }
        };
        
        // {"capabilities":{"textDocument":{"diagnostic":{"dynamicRegistration":false,"relatedDocumentSupport":true},"formatting":{"dynamicRegistration":false},"hover":{"contentFormat":["markdown"]},"inlayHint":{"dynamicRegistration":false},"publishDiagnostics":{"tagSupport":{"valueSet":[1,2]},"versionSupport":true},"rename":{"dynamicRegistration":false,"honorsChangeAnnotations":false,"prepareSupport":true},"signatureHelp":{"signatureInformation":{"activeParameterSupport":true,"documentationFormat":["markdown"],"parameterInformation":{"labelOffsetSupport":true}}}},"window":{"showDocument":{"support":true},"workDoneProgress":true},"workspace":{"applyEdit":true,"configuration":true,"diagnostic":{"refreshSupport":true},"didChangeConfiguration":{"dynamicRegistration":false},"didChangeWatchedFiles":{"dynamicRegistration":true,"relativePatternSupport":false},"executeCommand":{"dynamicRegistration":false},"fileOperations":{"didRename":true,"willRename":true},"inlayHint":{"refreshSupport":false},"symbol":{"dynamicRegistration":false},"workspaceEdit":{"documentChanges":true,"failureHandling":"abort","normalizesLineEndings":false,"resourceOperations":["create","rename","delete"]},"workspaceFolders":true}},"clientInfo":{"name":"helix","version":"25.07.1 (8de22be5)"},"processId":17329,"rootPath":"/Users/geertf","rootUri":null,"workspaceFolders":[]}
        
        // Generic Response with injected, optional Result
        // &todo: Add support for 'error'
        pub fn Response(Result: type) type {
            return struct {
                jsonrpc: String = "2.0",
                id: i32,
                result: ?*const Result,
            };
        }
        
        pub const InitializeResult = struct {
            capabilities: ServerCapabilities,
            serverInfo: ServerInfo,
        };
        
        pub const ReferenceContext = struct {
            includeDeclaration: ?bool = null,
            triggerCharacter: ?String = null,
            triggerKind: ?u32 = null,
            diagnostics: ?[]Diagnostic = null,
        };
        
        pub const Position = struct {
            line: u32 = 0,
            character: u32 = 0,
        };
        
        pub const Range = struct {
            start: Position = .{},
            end: Position = .{},
        };
        
        pub const Event = struct {
            added: []WorkspaceFolder = &.{},
            removed: []WorkspaceFolder = &.{},
        };
        
        pub const DocumentSymbol = struct {
            name: String = &.{},
            kind: u32 = 7,
            range: Range = .{},
            selectionRange: Range = .{},
        };
        
        pub const WorkspaceSymbol = struct {
            name: String = &.{},
            kind: u32 = 7,
            location: Location = .{},
            containerName: ?String = null,
            score: ?f32 = null,
        };
        
        pub const Location = struct {
            uri: String = &.{},
            range: Range = .{},
        };
        
        pub const TextDocumentItem = struct {
            uri: String,
            languageId: ?String = null,
            version: ?i32 = null,
            text: ?String = null,
        };
        
        pub const WorkspaceFolder = struct {
            name: String,
            uri: String,
        };
        
        pub const ContentChange = struct {
            range: ?Range = null,
            text: String,
        };
        
        pub const ClientInfo = struct {
            name: String,
            version: String,
        };
        
        pub const CompletionItem = struct {
            label: String,
            kind: u32,
        };
        
        pub const Diagnostic = struct {
            range: Range,
            message: String,
        };
        
        pub const Command = struct {
            title: String,
            command: String,
            arguments: ?[]const String = null,
        };
        
        pub const ClientCapabilities = struct {
            pub const General = struct {
                positionEncodings: []String,
            };
            pub const TextDocument = struct {
                pub const ResolveSupport = struct {
                    properties: []String,
                };
                pub const TagSupport = struct {
                    valueSet: []i64,
                };
                pub const CodeAction = struct {
                    pub const CodeActionLiteralSupport = struct {
                        pub const CodeActionKind = struct {
                            valueSet: []String,
                        };
                        codeActionKind: CodeActionKind,
                    };
                    codeActionLiteralSupport: CodeActionLiteralSupport,
                    dataSupport: bool,
                    disabledSupport: bool,
                    isPreferredSupport: bool,
                    resolveSupport: ResolveSupport,
                };
                pub const Completion = struct {
                    pub const CompletionItem = struct {
                        deprecatedSupport: bool,
                        insertReplaceSupport: bool,
                        resolveSupport: ResolveSupport,
                        snippetSupport: bool,
                        tagSupport: TagSupport,
                    };
                    pub const CompletionItemKind = struct {
                        // valueSet: []String = &.{},
                    };
                    completionItem: Completion.CompletionItem,
                    completionItemKind: CompletionItemKind,
                };
                pub const Formatting = struct {
                    dynamicRegistration: bool,
                };
                pub const Hover = struct {
                    contentFormat: []String,
                };
                pub const InlayHint = struct {
                    dynamicRegistration: bool,
                };
                pub const PublishDiagnostics = struct {
                    tagSupport: TagSupport,
                    versionSupport: bool,
                };
                pub const Rename = struct {
                    dynamicRegistration: bool,
                    honorsChangeAnnotations: bool,
                    prepareSupport: bool,
                };
                pub const SignatureHelp = struct {
                    pub const SignatureInformation = struct {
                        pub const ParameterInformation = struct {
                            labelOffsetSupport: bool,
                        };
                        activeParameterSupport: bool,
                        documentationFormat: []String,
                        parameterInformation: ParameterInformation,
                    };
                    signatureInformation: SignatureInformation,
                };
                pub const TextDocumentDiagnostic = struct {
                    dynamicRegistration: bool,
                    relatedDocumentSupport: bool,
                };
        
                codeAction: CodeAction,
                completion: Completion,
                formatting: Formatting,
                hover: Hover,
                inlayHint: InlayHint,
                publishDiagnostics: PublishDiagnostics,
                rename: Rename,
                signatureHelp: SignatureHelp,
                diagnostic: ?TextDocumentDiagnostic = null,
            };
            pub const Window = struct {
                pub const ShowDocument = struct {
                    support: bool,
                };
                workDoneProgress: bool,
                showDocument: ?ShowDocument = null,
            };
        
            general: General,
            textDocument: TextDocument,
            window: Window,
            workspace: Workspace,
            pub const Workspace = struct {
                pub const DidChangeConfiguration = struct {
                    dynamicRegistration: bool,
                };
                pub const DidChangeWatchedFiles = struct {
                    dynamicRegistration: bool,
                    relativePatternSupport: bool,
                };
                pub const ExecuteCommand = struct {
                    dynamicRegistration: bool,
                };
                pub const FileOperations = struct {
                    didRename: bool,
                    willRename: bool,
                };
                pub const InlayHint = struct {
                    refreshSupport: bool,
                };
                pub const Symbol = struct {
                    dynamicRegistration: bool,
                };
                pub const WorkspaceEdit = struct {
                    documentChanges: bool,
                    failureHandling: String,
                    normalizesLineEndings: bool,
                    resourceOperations: []String,
                };
                pub const WorkspaceDiagnostic = struct {
                    refreshSupport: bool,
                };
        
                applyEdit: bool,
                configuration: bool,
                didChangeConfiguration: DidChangeConfiguration,
                didChangeWatchedFiles: DidChangeWatchedFiles,
                executeCommand: ExecuteCommand,
                fileOperations: FileOperations,
                inlayHint: InlayHint,
                symbol: Symbol,
                workspaceEdit: WorkspaceEdit,
                workspaceFolders: bool,
                diagnostic: ?WorkspaceDiagnostic = null,
            };
        };
        
        pub const ServerCapabilities = struct {
            pub const Workspace = struct {
                pub const WorkspaceFolders = struct {
                    supported: bool,
                };
        
                workspaceFolders: ?WorkspaceFolders = null,
            };
            pub const TextDocumentSyncOptions = struct {
                openClose: ?bool = true,
                change: ?u32 = 2,
            };
            pub const CompletionOptions = struct {
                triggerCharacters: ?[]const String = null,
            };
            pub const ExecuteCommandOptions = struct {
                commands: []const String,
            };
        
            textDocumentSync: ?TextDocumentSyncOptions = null,
            completionProvider: ?CompletionOptions = null,
            documentSymbolProvider: ?bool = null,
            workspaceSymbolProvider: ?bool = null,
            declarationProvider: ?bool = null,
            definitionProvider: ?bool = null,
            typeDefinitionProvider: ?bool = null,
            implementationProvider: ?bool = null,
            referencesProvider: ?bool = null,
            codeActionProvider: ?bool = null,
            executeCommandProvider: ?ExecuteCommandOptions = null,
            workspace: ?Workspace = null,
        };
        
        pub const ServerInfo = struct {
            name: ?String = null,
            version: ?String = null,
        };
    };
};

// Export from 'src/fuzz.zig'
pub const fuzz = struct {
    // Only if needle constains upper-case letters, case-sensitive search will happen.
    // 'maybe_skip_count' can be used to return the number of characters that could not be matched.
    pub fn distance(needle_in: []const u8, haystack_in: []const u8, maybe_skip_count: ?*usize) f64 {
        // We wrap the computation of the total distance in a closure to support closure.indexOf() to take 'case_sensitive' into account
        var closure = struct {
            const Cl = @This();
    
            case_sensitive: bool = false,
            skip_count: usize = 0,
    
            fn total_distance(cl: *Cl, haystack: []const u8, needle: []const u8) f64 {
                for (needle) |ch|
                    if (std.ascii.isUpper(ch)) {
                        cl.case_sensitive = true;
                        break;
                    };
    
                var sum: f64 = 0.0;
                var offset: usize = 0;
                for (needle) |ch| {
                    if (offset >= haystack.len)
                        offset = 0;
                    const d = blk: {
                        if (cl.indexOf(haystack[offset..], ch)) |ix| {
                            defer offset += ix + 1;
                            break :blk ix;
                        } else if (cl.indexOf(haystack[0..offset], ch)) |ix| {
                            defer offset = ix + 1;
                            break :blk haystack.len - offset + ix;
                        } else {
                            cl.skip_count += 1;
                            break :blk haystack.len;
                        }
                    };
                    sum += std.math.log2(@as(f64, @floatFromInt(d + 1)));
                }
    
                return sum;
            }
    
            fn indexOf(cl: Cl, slice: []const u8, ch: u8) ?usize {
                return if (cl.case_sensitive)
                    std.mem.indexOfScalar(u8, slice, ch)
                else
                    std.ascii.indexOfIgnoreCase(slice, (&ch)[0..1]);
            }
        }{};
    
        const total_distance = closure.total_distance(haystack_in, needle_in);
        if (maybe_skip_count) |v|
            v.* = closure.skip_count;
    
        return if (needle_in.len > 0) total_distance / @as(f64, @floatFromInt(needle_in.len)) else 0.0;
    }
    
    pub fn max_distance(needle: []const u8, max_haystack_len: usize) f64 {
        if (needle.len == 0)
            return 0.0;
        return std.math.log2(@as(f64, @floatFromInt(max_haystack_len + 1)));
    }
    
};

// Export from 'src/algo.zig'
pub const algo = struct {
    pub fn anyOf(T: type, slice: []const T, predicate: anytype) bool {
        for (slice) |el|
            if (predicate.call(el))
                return true;
        return false;
    }
    
    pub fn allOf(T: type, slice: []const T, predicate: anytype) bool {
        for (slice) |el|
            if (!predicate.call(el))
                return false;
        return true;
    }
    
    pub fn countIf(T: type, slice: []const T, predicate: anytype) usize {
        var count: usize = 0;
        for (slice) |el| {
            if (predicate.call(el))
                count += 1;
        }
        return count;
    }
    
    pub fn indexOfFirst(T: type, slice: []const T, predicate: anytype) ?usize {
        for (slice, 0..) |el, ix0|
            if (predicate.call(el))
                return ix0;
        return null;
    }
    
};

// Export from 'src/opt.zig'
pub const opt = struct {
    pub fn value(x: anytype) ?@TypeOf(x) {
        return x;
    }
    pub fn none(T: type) ?T {
        return null;
    }
    
};

// Export from 'src/ansi.zig'
pub const ansi = struct {
    pub const Style = struct {
        const Self = @This();
        pub const Ground = struct {
            pub const Color = enum(u8) { Black = 0, Red, Green, Yellow, Blue, Magenta, Cyan, White };
            color: Color,
            intense: bool = false,
        };
    
        fg: ?Ground = null,
        bg: ?Ground = null,
        bold: bool = false,
        underline: bool = false,
        reset: bool = false,
    
        pub fn format(self: Self, w: *std.Io.Writer) !void {
            var print = struct {
                w: *std.Io.Writer,
                prefix: u8 = '[',
                fn value(my: *@This(), n: u8) !void {
                    try my.w.print("{c}{}", .{ my.prefix, n });
                    my.prefix = ';';
                }
            }{ .w = w };
    
            try w.writeByte(0x1b);
            if (self.reset) {
                try print.value(0);
            } else {
                if (!self.bold and !self.underline) {
                    try print.value(0);
                } else {
                    if (self.bold)
                        try print.value(1);
                    if (self.underline)
                        try print.value(4);
                }
                if (self.fg) |g|
                    try print.value(30 + @intFromEnum(g.color) + @as(u8, @intFromBool(g.intense)) * 60);
                if (self.bg) |g|
                    try print.value(40 + @intFromEnum(g.color) + @as(u8, @intFromBool(g.intense)) * 60);
            }
            try w.print("m", .{});
        }
    };
    
};
