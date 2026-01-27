const std = @import("std");

const tkn = @import("../tkn.zig");
const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");
const Parser = @import("Parser.zig");
const chore = @import("../chore.zig");
const filex = @import("../filex.zig");

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
        Section,
        Bullet,
        Checkbox,
        Capital,
        Code,
        Formula,
        Comment,
        Newline,
        Amp,
        Whitespace,
        Wikilink,
    };

    word: []const u8,
    kind: Kind,

    pub fn deinit(_: Self) void {}

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Term");
        defer n.deinit();
        n.attr("kind", self.kind);
        if (self.kind != .Newline)
            n.attr("word", self.word);
    }
    pub fn format(self: Self, w: *std.Io.Writer) !void {
        var n = naft.Node.root(w);
        defer n.deinit();
        self.write(&n);
    }
};

pub const Text = struct {
    const Self = @This();
    pub const Kind = enum { Section, Paragraph, Bullet, Line };
    kind: Kind,

    // During parsing, `ixr` is used to avoid dangling pointers.
    terms: union {
        ixr: idx.Range,
        slice: []const Term,
    },

    pub fn append(self: *Self, term: Term, terms: *Terms, a: std.mem.Allocator) !void {
        if (term.word.len > 0) {
            if (self.terms.ixr.empty())
                self.terms.ixr = .{ .begin = terms.items.len, .end = terms.items.len };
            try terms.append(a, term);
            self.terms.ixr.end += 1;
        }
    }

    pub fn write(self: Self, terms: []const Term, parent: *naft.Node) void {
        var n = parent.node("Text");
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
    pub const DefIx = amp.Def.Ix;
    pub const DefIxs = std.ArrayList(DefIx);
    pub const Def = struct {
        ix: DefIx,
        pos: filex.Pos,
        is_dependency: bool = false, // We cannot store this data in amp.Def since that is shared between different resolved amps
    };
    pub const Defs = std.ArrayList(Def);

    pub const File = struct {
        language: Language,
        terms: Terms = .{},
    };

    pub const Type = union(enum) {
        grove: void,
        folder: void,
        file: File,
        text: Text,

        pub fn isText(my: @This(), kind: Text.Kind) bool {
            return switch (my) {
                .text => |text| text.kind == kind,
                else => false,
            };
        }
    };

    a: std.mem.Allocator,

    type: Type = undefined,

    // Ref to a definition that is directly present in this Node
    // Is also added to org_amps
    def: ?Def = null,
    // Refs to resolved AMPs that are directly present in this Node
    // Only the first can be a def
    org_amps: Defs = .{},
    // Refs to resolved AMPs that are inherited
    // Move to Chore to gain 250MB memory
    // Maybe replace with a set. Do take into account that in Chore.value, the order currently influences ~status
    agg_amps: DefIxs = .{},

    // &perf: Only activate relevant fields depending on type
    path: []const u8 = &.{}, // Allocated on ArenaAllocator `tree.aa`: present many times
    content: []const u8 = &.{}, // Allocated on ArenaAllocator `tree.aa`: subslices are present many times

    content_rows: idx.Range = .{},
    content_cols: idx.Range = .{},

    grove_id: ?usize = null,
    chore_id: ?usize = null,

    pub fn deinit(self: *Self) void {
        self.org_amps.deinit(self.a);
        self.agg_amps.deinit(self.a);
        switch (self.type) {
            .file => |*file| {
                for (file.terms.items) |*item|
                    item.deinit();
                file.terms.deinit(self.a);
            },

            else => {},
        }
    }

    pub fn write(self: Self, parent: *naft.Node, maybe_id: ?Tree.Id) void {
        var n = parent.node("dto.Node");
        defer n.deinit();
        if (maybe_id) |id|
            n.attr("id", id);
        n.attr("type", self.type);
        n.attr("content", self.content);
        if (self.chore_id) |id|
            n.attr("chore_id", id);
        self.content_rows.write(&n, "rows");
        self.content_cols.write(&n, "cols");
        switch (self.type) {
            .file => |file| {
                for (file.terms.items) |term|
                    term.write(&n);
            },
            .text => |text| {
                var nn = n.node("Text");
                defer nn.deinit();
                nn.attr("kind", text.kind);
            },
            else => {},
        }
    }
};

pub const Language = enum {
    Markdown,
    Cish,
    Ruby,
    Python,
    Lua,
    Text,

    pub fn from_extension(ext: []const u8) ?Language {
        if (std.mem.eql(u8, ext, ".md"))
            return Language.Markdown;

        if (std.mem.eql(u8, ext, ".rb"))
            return Language.Ruby;

        if (std.mem.eql(u8, ext, ".py"))
            return Language.Python;

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
