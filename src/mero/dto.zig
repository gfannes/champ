const std = @import("std");

const tkn = @import("../tkn.zig");
const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const Parser = @import("parser.zig").Parser;

const naft = @import("rubr").naft;
const strings = @import("rubr").strings;
const walker = @import("rubr").walker;
const Log = @import("rubr").log.Log;

pub const Grove = struct {
    const Self = @This();
    const String = std.ArrayList(u8);

    log: *const Log,
    name: ?[]const u8 = null,
    path: ?[]const u8 = null,
    a: std.mem.Allocator,

    pub fn init(log: *const Log, a: std.mem.Allocator) !Self {
        return Self{ .log = log, .a = a };
    }
    pub fn deinit(self: *Self) void {
        if (self.name) |name|
            self.a.free(name);
        if (self.path) |path|
            self.a.free(path);
    }

    pub fn load(self: *Self, cfg_grove: *const cfg.Grove) !void {
        var content = String.init(self.a);
        defer content.deinit();

        var cb = Cb{ .outer = self, .cfg_grove = cfg_grove, .content = &content, .a = self.a };

        const dir = try std.fs.openDirAbsolute(cfg_grove.path, .{});

        var w = try walker.Walker.init(self.a);
        defer w.deinit();
        try w.walk(dir, &cb);

        self.name = try self.a.dupe(u8, cfg_grove.name);
        self.path = try self.a.dupe(u8, cfg_grove.path);
    }

    const Cb = struct {
        outer: *const Self,
        cfg_grove: *const cfg.Grove,
        content: *String,
        a: std.mem.Allocator,

        file_count: usize = 0,

        pub fn call(my: *Cb, dir: std.fs.Dir, path: []const u8, offsets: walker.Offsets) !void {
            const name = path[offsets.name..];

            if (my.cfg_grove.include) |include| {
                const ext = std.fs.path.extension(name);
                if (!strings.contains(u8, include, ext))
                    // Skip this extension
                    return;
            }

            const file = try dir.openFile(name, .{});
            defer file.close();

            const stat = try file.stat();

            const size_is_ok = if (my.cfg_grove.max_size) |max_size| stat.size < max_size else true;
            if (!size_is_ok)
                return;

            if (my.cfg_grove.max_count) |max_count|
                if (my.file_count >= max_count)
                    return;
            my.file_count += 1;

            try my.content.resize(stat.size);
            _ = try file.readAll(my.content.items);

            const my_ext = std.fs.path.extension(name);
            if (mero.Language.from_extension(my_ext)) |language| {
                var parser = mero.Parser.init(my.a, language);
                var root = try parser.parse(my.content.items);
                errdefer root.deinit();

                var mero_file = try mero.File.init(root, path, my.a);
                defer mero_file.deinit();

                if (my.outer.log.level(1)) |out| {
                    var cb = struct {
                        path: []const u8,
                        o: @TypeOf(out),
                        did_log_filename: bool = false,

                        pub fn call(s: *@This(), amp: []const u8) !void {
                            if (!s.did_log_filename) {
                                try s.o.print("Filename: {s}\n", .{s.path});
                                s.did_log_filename = true;
                            }
                            try s.o.print("{s}\n", .{amp});
                        }
                    }{ .path = path, .o = out };
                    try mero_file.root.each_amp(&cb);
                }
            } else {
                try my.outer.log.warning("Unsupported extension '{s}' for '{}' '{s}'\n", .{ my_ext, dir, path });
            }
        }
    };
};

pub const Term = struct {
    const Self = @This();
    pub const Kind = enum {
        Text,
        Link,
        Code,
        Formula,
        Comment,
        Newline,
        Amp,
    };

    word: []const u8,
    kind: Kind,

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Term");
        defer n.deinit();
        n.attr("kind", self.kind);
        if (self.kind != Kind.Newline)
            n.attr("word", self.word);
    }
};

pub const Line = struct {
    const Self = @This();
    const Terms = std.ArrayList(Term);

    terms: Terms,

    pub fn init(ma: std.mem.Allocator) Line {
        return Self{ .terms = Terms.init(ma) };
    }
    pub fn deinit(self: *Self) void {
        self.terms.deinit();
    }

    pub fn append(self: *Self, term: Term) !void {
        if (term.word.len > 0)
            try self.terms.append(term);
    }

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Line");
        defer n.deinit();
        for (self.terms.items) |term| {
            // n.attr1(term.word);
            term.write(&n);
        }
    }
};

pub const Node = struct {
    const Self = @This();
    const Childs = std.ArrayList(Node);
    pub const Type = enum { Root, Section, Paragraph, Bullets, Code };

    type: ?Type = null,
    line: Line,
    childs: Childs,
    ma: std.mem.Allocator,

    pub fn init(ma: std.mem.Allocator) Self {
        return Self{ .line = Line.init(ma), .childs = Childs.init(ma), .ma = ma };
    }
    pub fn deinit(self: *Self) void {
        self.line.deinit();
        for (self.childs.items) |*child|
            child.deinit();
        self.childs.deinit();
    }

    pub fn each_amp(self: Self, cb: anytype) !void {
        for (self.line.terms.items) |term| {
            if (term.kind == Term.Kind.Amp)
                try cb.call(term.word);
        }
        for (self.childs.items) |child| {
            try child.each_amp(cb);
        }
    }

    pub fn goc_child(self: *Self, ix: usize) !*Node {
        while (ix >= self.childs.items.len) {
            try self.childs.append(Node.init(self.ma));
        }
        return &self.childs.items[ix];
    }

    pub fn push_child(self: *Self, n: Node) !void {
        return self.childs.append(n);
    }

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Node");
        defer n.deinit();
        if (self.type) |t| n.attr("type", t);

        self.line.write(&n);
        for (self.childs.items) |child| {
            child.write(&n);
        }
    }
};

pub const File = struct {
    const Self = @This();

    root: Node,
    name: []const u8,
    ma: std.mem.Allocator,

    pub fn init(root: Node, name: []const u8, ma: std.mem.Allocator) !File {
        return File{ .root = root, .name = try ma.dupe(u8, name), .ma = ma };
    }
    pub fn deinit(self: *Self) void {
        self.root.deinit();
        self.ma.free(self.name);
    }
};

pub const Language = enum {
    Markdown,
    Cish,
    Ruby,
    Lua,
    Text,

    pub fn from_extension(ext: []const u8) ?Language {
        if (std.mem.eql(u8, ext, ".md"))
            return Language.Markdown;

        if (std.mem.eql(u8, ext, ".rb"))
            return Language.Ruby;

        if (std.mem.eql(u8, ext, ".lua"))
            return Language.Lua;

        if (std.mem.eql(u8, ext, ".txt"))
            return Language.Text;

        const cish_exts = [_][]const u8{ ".c", ".h", ".hpp", ".cpp", ".chai" };
        for (cish_exts) |el|
            if (std.mem.eql(u8, ext, el))
                return Language.Cish;

        return null;
    }
};
