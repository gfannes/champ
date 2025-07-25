const std = @import("std");

const tkn = @import("../tkn.zig");
const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");
const Parser = @import("parser.zig").Parser;
const chore = @import("../chore.zig");

const rubr = @import("rubr");
const naft = rubr.naft;
const strings = rubr.strings;
const walker = rubr.walker;
const Log = rubr.log.Log;
const idx = rubr.idx;
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
        Bullet,
        Checkbox,
        Capital,
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

    terms_ixr: idx.Range = .{},

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
    pub const Pos = struct {
        row: usize,
        cols: rubr.idx.Range,
    };
    pub const Amp = struct {
        ix: chore.Amp.Ix,
        pos: Pos,
    };
    const Amps = std.ArrayList(Amp);

    pub const Type = enum { Grove, Folder, File, Root, Section, Paragraph, Bullet, Code, Line, Unknown };

    type: Type = Type.Unknown,
    language: ?Language = null,

    // Ref to a definition that is directly present in this Node
    // Is also added to org_amps
    def: ?Amp = null,
    // Refs to resolved AMPs that are directly present in this Node
    // Only the first can be a def
    org_amps: Amps,
    // Refs to resolved AMPs that are inherited
    agg_amps: Amps,

    // &perf: Only activate relevant fields depending on type
    line: Line = .{},
    path: []const u8 = &.{},
    content: []const u8 = &.{},
    terms: Terms,

    content_rows: idx.Range = .{},
    content_cols: idx.Range = .{},

    grove_id: ?usize = null,

    a: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) Self {
        return Self{
            .org_amps = Amps.init(a),
            .agg_amps = Amps.init(a),
            .terms = Terms.init(a),
            .a = a,
        };
    }
    pub fn deinit(self: *Self) void {
        self.org_amps.deinit();
        self.agg_amps.deinit();
        for (self.terms.items) |*item|
            item.deinit();
        self.terms.deinit();
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

        const cish_exts = [_][]const u8{ ".c", ".h", ".hpp", ".cpp", ".chai", ".zig", ".zon", ".rs", ".java" };
        for (cish_exts) |el|
            if (std.mem.eql(u8, ext, el))
                return Language.Cish;

        return null;
    }
};
