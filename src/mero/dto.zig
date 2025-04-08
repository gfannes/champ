const std = @import("std");

const tkn = @import("../tkn.zig");
const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const Parser = @import("parser.zig").Parser;

const naft = @import("rubr").naft;
const strings = @import("rubr").strings;
const walker = @import("rubr").walker;
const Log = @import("rubr").log.Log;
const index = @import("rubr").index;

pub const Grove = struct {
    const Self = @This();
    const String = std.ArrayList(u8);
    const Files = std.ArrayList(File);

    log: *const Log,
    name: ?[]const u8 = null,
    path: ?[]const u8 = null,
    files: Files,
    a: std.mem.Allocator,

    pub fn init(log: *const Log, a: std.mem.Allocator) !Self {
        return Self{ .log = log, .files = Files.init(a), .a = a };
    }
    pub fn deinit(self: *Self) void {
        if (self.name) |name|
            self.a.free(name);
        if (self.path) |path|
            self.a.free(path);
        for (self.files) |file|
            file.deinit();
        self.files.deinit();
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
        outer: *Self,
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
                var parser = try mero.Parser.init(path, language, my.content.items, my.a);
                defer parser.deinit();

                try my.outer.files.append(try parser.parse());
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

    terms_ixr: index.Range = .{},

    pub fn append(self: *Self, term: Term, terms: *File.Terms) !void {
        if (term.word.len > 0) {
            if (self.terms_ixr.empty())
                self.terms_ixr = .{ .begin = terms.items.len, .end = terms.items.len };
            try terms.append(term);
            self.terms_ixr.end += 1;
        }
    }

    pub fn write(self: Self, terms: []const Term, parent: *naft.Node) void {
        var n = parent.node("Line");
        defer n.deinit();
        for (self.terms_ixr.begin..self.terms_ixr.end) |ix| {
            // n.attr1(term.word);
            terms[ix].write(&n);
        }
    }
};

pub const Node = struct {
    const Self = @This();
    const Childs = std.ArrayList(Node);
    pub const Type = enum { Root, Section, Paragraph, Bullets, Code };

    type: ?Type = null,
    line: Line = .{},
    childs: Childs,
    a: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) Self {
        return Self{ .childs = Childs.init(a), .a = a };
    }
    pub fn deinit(self: *Self) void {
        for (self.childs.items) |*child|
            child.deinit();
        self.childs.deinit();
    }

    pub fn each_amp(self: Self, terms: []const Term, cb: anytype) !void {
        for (self.line.terms_ixr.begin..self.line.terms_ixr.end) |ix| {
            const term: *const Term = &terms[ix];
            if (term.kind == Term.Kind.Amp)
                try cb.call(term.word);
        }
        for (self.childs.items) |child| {
            try child.each_amp(terms, cb);
        }
    }

    pub fn goc_child(self: *Self, ix: usize) !*Node {
        while (ix >= self.childs.items.len) {
            try self.childs.append(Node.init(self.a));
        }
        return &self.childs.items[ix];
    }

    pub fn push_child(self: *Self, n: Node) !void {
        return self.childs.append(n);
    }

    pub fn write(self: Self, terms: []const Term, parent: *naft.Node) void {
        var n = parent.node("Node");
        defer n.deinit();
        if (self.type) |t| n.attr("type", t);

        self.line.write(terms, &n);
        for (self.childs.items) |child| {
            child.write(terms, &n);
        }
    }
};

pub const File = struct {
    const Self = @This();
    const Terms = std.ArrayList(Term);

    root: Node,
    path: []const u8,
    content: []const u8,
    terms: Terms,
    a: std.mem.Allocator,

    pub fn init(path: []const u8, content: []const u8, a: std.mem.Allocator) !File {
        return File{ .root = Node.init(a), .path = try a.dupe(u8, path), .content = try a.dupe(u8, content), .terms = Terms.init(a), .a = a };
    }
    pub fn deinit(self: *Self) void {
        self.root.deinit();
        self.a.free(self.path);
        self.a.free(self.content);
        self.terms.deinit();
    }

    pub fn each_amp(self: Self, cb: anytype) !void {
        try self.root.each_amp(self.terms.items, cb);
    }
    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("File");
        defer n.deinit();

        n.attr("path", self.path);
        self.root.write(self.terms.items, &n);
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
