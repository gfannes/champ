const std = @import("std");

const tkn = @import("../tkn.zig");
const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");
const Parser = @import("parser.zig").Parser;

const rubr = @import("rubr");
const naft = rubr.naft;
const strings = rubr.strings;
const walker = rubr.walker;
const Log = rubr.log.Log;
const index = rubr.index;
const tree = rubr.tree;

pub const Error = error{
    ExpectedOffsets,
};

pub const Terms = std.ArrayList(Term);

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

    pub fn deinit(_: Self) void {}

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

    pub fn append(self: *Self, term: Term, terms: *Terms) !void {
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

pub const Tree = tree.Tree(Node);

pub const Node = struct {
    const Self = @This();
    const Amps = std.ArrayList(amp.Path);

    pub const Type = enum { Grove, Folder, File, Root, Section, Paragraph, Bullet, Code, Line, Unknown };

    type: Type = Type.Unknown,
    language: ?Language = null,

    // Will contain resolved Amps, only the first can be a definition
    orgs: Amps,

    // &perf: Only activate relevant fields depending on type
    line: Line = .{},
    path: []const u8 = &.{},
    content: []const u8 = &.{},
    terms: Terms,

    content_rows: index.Range = .{},
    content_cols: index.Range = .{},

    a: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) Self {
        return Self{
            .orgs = Amps.init(a),
            .terms = Terms.init(a),
            .a = a,
        };
    }
    pub fn deinit(self: *Self) void {
        const array_lists = .{
            &self.orgs,
            &self.terms,
        };
        inline for (array_lists) |al| {
            for (al.items) |*e|
                e.deinit();
            al.deinit();
        }
        self.a.free(self.path);
        self.a.free(self.content);
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

        const cish_exts = [_][]const u8{ ".c", ".h", ".hpp", ".cpp", ".chai", ".zig", ".zon", ".rs" };
        for (cish_exts) |el|
            if (std.mem.eql(u8, ext, el))
                return Language.Cish;

        return null;
    }
};
