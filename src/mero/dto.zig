const std = @import("std");

const tkn = @import("../tkn.zig");
const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");
const Parser = @import("parser.zig").Parser;

const naft = @import("rubr").naft;
const strings = @import("rubr").strings;
const walker = @import("rubr").walker;
const Log = @import("rubr").log.Log;
const index = @import("rubr").index;
const Strange = @import("rubr").strange.Strange;

pub const Error = error{
    ExpectedOffsets,
};

pub const Grove = struct {
    const Self = @This();
    const Buffer = std.ArrayList(u8);
    const Folders = std.ArrayList(Folder);
    const Files = std.ArrayList(File);

    log: *const Log,
    name: ?[]const u8 = null,
    path: ?[]const u8 = null,
    folders: Folders,
    files: Files,
    a: std.mem.Allocator,

    pub fn init(log: *const Log, a: std.mem.Allocator) !Self {
        return Self{
            .log = log,
            .folders = Folders.init(a),
            .files = Files.init(a),
            .a = a,
        };
    }
    pub fn deinit(self: *Self) void {
        if (self.name) |name|
            self.a.free(name);
        if (self.path) |path|
            self.a.free(path);
        for (self.folders.items) |*folder|
            folder.deinit();
        self.folders.deinit();
        for (self.files.items) |*file|
            file.deinit();
        self.files.deinit();
    }

    pub fn load(self: *Self, cfg_grove: *const cfg.Grove) !void {
        var buffer = Buffer.init(self.a);
        defer buffer.deinit();

        var cb = Cb.init(self, cfg_grove, &buffer, self.a);
        defer cb.deinit();

        const dir = try std.fs.openDirAbsolute(cfg_grove.path, .{});

        var w = try walker.Walker.init(self.a);
        defer w.deinit();
        try w.walk(dir, &cb);

        self.name = try self.a.dupe(u8, cfg_grove.name);
        self.path = try self.a.dupe(u8, cfg_grove.path);
    }

    const Cb = struct {
        const Stack = std.ArrayList(usize);

        outer: *Self,
        cfg_grove: *const cfg.Grove,
        buffer: *Buffer,
        folder_ix_stack: Stack,
        a: std.mem.Allocator,

        file_count: usize = 0,

        pub fn init(outer: *Self, cfg_grove: *const cfg.Grove, buffer: *Buffer, a: std.mem.Allocator) Cb {
            return Cb{
                .outer = outer,
                .cfg_grove = cfg_grove,
                .buffer = buffer,
                .folder_ix_stack = Stack.init(a),
                .a = a,
            };
        }
        pub fn deinit(my: *Cb) void {
            my.folder_ix_stack.deinit();
        }

        pub fn call(my: *Cb, dir: std.fs.Dir, path: []const u8, maybe_offsets: ?walker.Offsets, kind: walker.Kind) !void {
            switch (kind) {
                walker.Kind.Enter => {
                    var name: []const u8 = undefined;
                    if (maybe_offsets) |offsets| {
                        name = path[offsets.name..];
                    } else {
                        name = "<ROOT>";
                    }

                    try my.folder_ix_stack.append(my.outer.folders.items.len);

                    try my.outer.folders.append(try Folder.init(name, my.a));
                },
                walker.Kind.Leave => {
                    _ = my.folder_ix_stack.pop();
                },
                walker.Kind.File => {
                    const offsets = maybe_offsets orelse return Error.ExpectedOffsets;
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

                    try my.buffer.resize(stat.size);
                    _ = try file.readAll(my.buffer.items);

                    const my_ext = std.fs.path.extension(name);
                    if (mero.Language.from_extension(my_ext)) |language| {
                        var parser = try mero.Parser.init(path, language, my.buffer.items, my.a);
                        defer parser.deinit();

                        try my.outer.files.append(try parser.parse());
                    } else {
                        try my.outer.log.warning("Unsupported extension '{s}' for '{}' '{s}'\n", .{ my_ext, dir, path });
                    }
                },
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
        Whitespace,
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
    const Amps = std.ArrayList(amp.Path);

    pub const Type = enum { Root, Section, Paragraph, Bullets, Code };

    type: ?Type = null,
    line: Line = .{},

    childs: Childs,
    parent: ?*Node = null,
    orgs: Amps,
    defs: Amps,

    a: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) Self {
        return Self{
            .childs = Childs.init(a),
            .orgs = Amps.init(a),
            .defs = Amps.init(a),
            .a = a,
        };
    }
    pub fn deinit(self: *Self) void {
        const array_lists = .{
            &self.childs,
            &self.orgs,
            &self.defs,
        };
        inline for (array_lists) |al| {
            for (al.items) |*e|
                e.deinit();
            al.deinit();
        }
    }

    pub fn dfsNode(self: *Self, parent: ?*Self, call_before: bool, cb: anytype) !void {
        if (call_before)
            try cb.call(self, parent);

        for (self.childs.items) |*child|
            try child.dfsNode(self, call_before, cb);

        if (!call_before)
            try cb.call(self, parent);
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

pub const Folder = struct {
    const Self = @This();

    root: Node,
    path: []const u8,
    a: std.mem.Allocator,

    pub fn init(path: []const u8, a: std.mem.Allocator) !Self {
        return Self{
            .root = Node.init(a),
            .path = try a.dupe(u8, path),
            .a = a,
        };
    }
    pub fn deinit(self: *Self) void {
        self.root.deinit();
        self.a.free(self.path);
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
        return File{
            .root = Node.init(a),
            .path = try a.dupe(u8, path),
            .content = try a.dupe(u8, content),
            .terms = Terms.init(a),
            .a = a,
        };
    }
    pub fn deinit(self: *Self) void {
        self.root.deinit();
        self.a.free(self.path);
        self.a.free(self.content);
        self.terms.deinit();
    }

    pub fn initOrgsDefs(self: *Self) !void {
        var cb = struct {
            const My = @This();

            terms: *const Terms,
            a: std.mem.Allocator,

            pub fn call(my: *My, child: *Node, _: ?*Node) !void {
                for (child.line.terms_ixr.begin..child.line.terms_ixr.end) |term_ix| {
                    const term = &my.terms.items[term_ix];
                    if (term.kind == Term.Kind.Amp) {
                        var strange = Strange{ .content = term.word };
                        if (try amp.Path.parse(&strange, my.a)) |path|
                            if (path.is_definition)
                                try child.defs.append(path)
                            else
                                try child.orgs.append(path);
                    }
                }
            }
        }{ .terms = &self.terms, .a = self.a };

        try self.root.dfsNode(null, true, &cb);
    }

    pub fn each_amp(self: Self, cb: anytype) !void {
        try self.root.each_amp(self.terms.items, cb);
    }

    pub const Iter = struct {
        pub const Value = struct {
            content: []const u8,
            line: usize,
            start: usize,
            end: usize,
        };

        outer: *const File,
        term_ix: usize = 0,
        line_ix: usize = 0,
        line_start: [*]const u8,

        pub fn next(self: *Iter) ?Value {
            while (self.term_ix < self.outer.terms.items.len) {
                const term = &self.outer.terms.items[self.term_ix];
                defer self.term_ix += 1;
                switch (term.kind) {
                    Term.Kind.Amp => {
                        const start = term.word.ptr - self.line_start;
                        return Value{
                            .content = term.word,
                            .line = self.line_ix,
                            .start = start,
                            .end = start + term.word.len,
                        };
                    },
                    Term.Kind.Newline => {
                        self.line_ix += term.word.len;
                        self.line_start = term.word.ptr + term.word.len;
                    },
                    else => {},
                }
            }
            return null;
        }
    };
    pub fn iter(self: *const Self) Iter {
        return Iter{ .outer = self, .line_start = self.content.ptr };
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

        const cish_exts = [_][]const u8{ ".c", ".h", ".hpp", ".cpp", ".chai", ".zig", ".rs" };
        for (cish_exts) |el|
            if (std.mem.eql(u8, ext, el))
                return Language.Cish;

        return null;
    }
};
