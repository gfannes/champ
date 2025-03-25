const std = @import("std");
const ut = std.testing;

const naft = @import("rubr").naft;

const tkn = @import("tkn.zig");

pub const Error = error{
    UnexpectedState,
};

pub const Term = struct {
    const Self = @This();
    pub const Kind = enum {
        Text,
        Link,
        Code,
        Comment,
    };

    word: []const u8,
    kind: Kind,

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Term");
        defer n.deinit();
        n.attr("kind", self.kind);
        if (self.word.len > 0 and self.word[0] != '\n')
            n.attr("word", self.word)
        else
            n.attr("word", "<newline>");
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
        for (self.terms.items) |term|
            n.attr1(term.word);
    }
};

pub const Node = struct {
    const Self = @This();
    const Childs = std.ArrayList(Node);
    const Type = enum { Root, Section, Paragraph, Bullets };

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

pub const Language = enum {
    Markdown,
    Cish,
    Ruby,
    Text,

    pub fn from_extension(ext: []const u8) ?Language {
        if (std.mem.eql(u8, ext, ".md"))
            return Language.Markdown;

        if (std.mem.eql(u8, ext, ".rb"))
            return Language.Ruby;

        if (std.mem.eql(u8, ext, ".txt"))
            return Language.Text;

        const cish_exts = [_][]const u8{ ".c", ".h", ".hpp", ".cpp", ".chai" };
        for (cish_exts) |el|
            if (std.mem.eql(u8, ext, el))
                return Language.Cish;

        return null;
    }
};

pub const Parser = struct {
    const Self = @This();
    const Strings = std.ArrayList([]const u8);

    ma: std.mem.Allocator,
    language: Language,

    next_token: ?tkn.Token = null,
    tokenizer: tkn.Tokenizer = undefined,

    pub fn init(ma: std.mem.Allocator, language: Language) Self {
        return Self{ .ma = ma, .language = language };
    }

    pub fn parse(self: *Self, content: []const u8) !Node {
        var root = Node.init(self.ma);
        errdefer root.deinit();
        root.type = Node.Type.Root;

        self.tokenizer = tkn.Tokenizer.init(content);
        switch (self.language) {
            Language.Markdown => while (true) {
                if (try self.pop_section()) |el|
                    try root.push_child(el)
                else if (try self.pop_paragraph()) |el|
                    try root.push_child(el)
                else if (try self.pop_bullets()) |el|
                    try root.push_child(el)
                else
                    break;
            },
            else => while (true) {
                if (try self.pop_line()) |line|
                    try root.push_child(line)
                else
                    break;
            },
        }

        return root;
    }

    fn pop_line(self: *Self) !?Node {
        if (self.empty())
            return null;

        var n = Node.init(self.ma);
        errdefer n.deinit();

        switch (self.language) {
            Language.Markdown, Language.Text => try self.pop_line_text(&n),
            Language.Cish, Language.Ruby => try self.pop_line_with_comment(&n),
        }

        return n;
    }

    fn pop_line_text(self: *Self, n: *Node) !void {
        if (self.pop_text()) |text|
            try n.line.append(text);
    }
    fn pop_text(self: *Self) ?Term {
        var maybe_term: ?Term = null;
        while (self.next()) |token| {
            if (is_newline(token))
                break;

            if (maybe_term) |*term|
                term.word.len += token.word.len
            else
                maybe_term = Term{ .word = token.word, .kind = Term.Kind.Text };
        }
        return maybe_term;
    }

    fn pop_line_with_comment(self: *Self, n: *Node) !void {
        if (self.pop_code()) |code|
            try n.line.append(code);
        if (self.pop_comment()) |comment|
            try n.line.append(comment);
    }
    fn pop_code(self: *Self) ?Term {
        var maybe_term: ?Term = null;

        while (true) {
            if (self.peek()) |token| {
                if (is_comment(token, self.language))
                    break;
            } else break;

            if (self.next()) |token| {
                if (is_newline(token))
                    break;

                if (maybe_term) |*term|
                    term.word.len += token.word.len
                else
                    maybe_term = Term{ .word = token.word, .kind = Term.Kind.Code };
            } else unreachable;
        }

        return maybe_term;
    }
    fn pop_comment(self: *Self) ?Term {
        if (self.peek()) |first_token| {
            if (!is_comment(first_token, self.language))
                return null;

            var term = Term{ .word = first_token.word, .kind = Term.Kind.Comment };
            term.word.len = 0;

            while (self.next()) |token| {
                if (is_newline(token))
                    return term;
                term.word.len += token.word.len;
            }
            return term;
        }
        return null;
    }

    fn pop_section(self: *Self) !?Node {
        if (self.peek()) |first_token| {
            if (is_title(first_token)) |my_depth| {
                var n = try self.pop_line() orelse unreachable;
                n.type = Node.Type.Section;

                while (self.peek()) |token| {
                    if (is_title(token)) |depth| {
                        if (depth <= my_depth)
                            // This is the start of a section with a depth too low: we cannot nest
                            break;
                        try n.push_child(try self.pop_section() orelse unreachable);
                    } else if (try self.pop_paragraph()) |p| {
                        try n.push_child(p);
                    } else if (try self.pop_bullets()) |p| {
                        try n.push_child(p);
                    } else break;
                }

                return n;
            }
        }
        return null;
    }

    fn pop_paragraph(self: *Self) !?Node {
        if (self.peek()) |first_token| {
            if (is_line(first_token)) {
                var n = try self.pop_line() orelse unreachable;
                n.type = Node.Type.Paragraph;

                while (try self.pop_bullets()) |p| {
                    try n.push_child(p);
                }
                return n;
            }
        }
        return null;
    }

    fn pop_bullets(self: *Self) !?Node {
        if (self.peek()) |first_token| {
            if (is_bullet(first_token)) |my_depth| {
                var n = try self.pop_line() orelse unreachable;
                n.type = Node.Type.Bullets;

                while (self.peek()) |token| {
                    if (is_bullet(token)) |depth| {
                        if (depth <= my_depth)
                            // This is the start of a section with a depth too low: we cannot nest
                            break;
                        try n.push_child(try self.pop_bullets() orelse unreachable);
                    } else break;
                }
                return n;
            }
        }
        return null;
    }

    fn is_title(t: tkn.Token) ?usize {
        return if (t.symbol == tkn.Symbol.Hashtag) t.word.len else null;
    }
    fn is_line(t: tkn.Token) bool {
        return t.symbol != tkn.Symbol.Hashtag and t.symbol != tkn.Symbol.Space and t.symbol != tkn.Symbol.Minus and t.symbol != tkn.Symbol.Star;
    }
    fn is_bullet(t: tkn.Token) ?usize {
        return if (t.symbol == tkn.Symbol.Space)
            t.word.len
        else if (t.symbol == tkn.Symbol.Minus or t.symbol == tkn.Symbol.Star)
            0
        else
            null;
    }
    fn is_comment(t: tkn.Token, language: Language) bool {
        return switch (language) {
            Language.Cish => t.symbol == tkn.Symbol.Slash,
            Language.Ruby => t.symbol == tkn.Symbol.Hashtag,
            else => false,
        };
    }
    fn is_newline(t: tkn.Token) bool {
        return t.symbol == tkn.Symbol.Newline;
    }

    fn next(self: *Self) ?tkn.Token {
        if (self.next_token != null) {
            defer self.next_token = null;
            return self.next_token;
        }
        return self.tokenizer.next();
    }
    fn peek(self: *Self) ?tkn.Token {
        if (self.next_token == null)
            self.next_token = self.tokenizer.next();
        return self.next_token;
    }
    fn empty(self: *Self) bool {
        if (self.next_token == null)
            self.next_token = self.tokenizer.next();
        return self.next_token == null;
    }
};

test "Parser.parse()" {
    {
        var parser = Parser.init(ut.allocator, Language.Markdown);

        const content = "# Title1\n\n## Section\n\nLine\n- Bullet\n# Title2\nLine\n# Title3\n - Bullet\nLine\n# Title 4\n- b\n - bb\n- c";

        var root = try parser.parse(content);
        defer root.deinit();

        var n = naft.Node.init(null);
        root.write(&n);
    }
    {
        var parser = Parser.init(ut.allocator, Language.Cish);

        const content = "#include <iostream>\nint main(){\n  std::cout << \"Hello world.\" << std::endl; // &todo: place real program here\nreturn 0;\n}";

        var root = try parser.parse(content);
        defer root.deinit();

        var n = naft.Node.init(null);
        root.write(&n);
    }
}
