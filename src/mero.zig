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
    const Type = enum { Root, Section, Paragraph, Bullets, Code };

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
                if (try self.pop_section_node()) |el| {
                    try root.push_child(el);
                } else if (try self.pop_paragraph_node()) |el| {
                    try root.push_child(el);
                } else if (try self.pop_bullets_node()) |el| {
                    try root.push_child(el);
                } else {
                    break;
                }
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
        if (self.tokenizer.empty())
            return null;

        var n = Node.init(self.ma);
        errdefer n.deinit();

        switch (self.language) {
            Language.Markdown => try self.pop_markdown_text(&n),
            Language.Text => try self.pop_text(&n),
            Language.Cish, Language.Ruby => try self.pop_code_comment_text(&n),
        }

        return n;
    }

    fn pop_markdown_text(self: *Self, n: *Node) !void {
        while (self.tokenizer.peek()) |token| {
            if (is_newline(token)) {
                try n.line.append(self.pop_newline_term() orelse unreachable);
                break;
            }
            if (is_amp_start(self.tokenizer.current(), token)) {
                if (self.pop_amp_term()) |amp| {
                    try n.line.append(amp);
                    continue;
                }
            }
            if (self.pop_markdown_code_term()) |code| {
                try n.line.append(code);
                continue;
            }
            if (self.pop_markdown_formula_term()) |formula| {
                try n.line.append(formula);
                continue;
            }
            if (self.pop_comment_start()) |comment_start| {
                std.debug.assert(self.language == Language.Markdown);

                var comment = comment_start;
                var maybe_past: ?tkn.Token = null;
                while (self.tokenizer.next()) |current| {
                    comment.word.len += current.word.len;
                    if (maybe_past) |past| {
                        if (past.symbol == tkn.Symbol.Minus and past.word.len >= 2 and current.symbol == tkn.Symbol.CloseAngle)
                            break;
                    }
                    maybe_past = current;
                }
                try n.line.append(comment);
                continue;
            }
            try n.line.append(self.pop_text_term() orelse unreachable);
        }
    }

    fn pop_text(self: *Self, n: *Node) !void {
        while (self.tokenizer.peek()) |token| {
            if (is_newline(token)) {
                try n.line.append(self.pop_newline_term() orelse unreachable);
                break;
            }
            if (is_amp_start(self.tokenizer.current(), token)) {
                if (self.pop_amp_term()) |amp| {
                    try n.line.append(amp);
                    continue;
                }
            }
            try n.line.append(self.pop_text_term() orelse unreachable);
        }
    }

    // &todo: handle multiline comments
    fn pop_code_comment_text(self: *Self, n: *Node) !void {
        var found_comment = false;
        while (self.tokenizer.peek()) |token| {
            if (is_newline(token)) {
                try n.line.append(self.pop_newline_term() orelse unreachable);
                break;
            }
            if (!found_comment) {
                if (self.pop_comment_start()) |comment| {
                    try n.line.append(comment);
                    found_comment = true;

                    // We only check for Amp right after the comment
                    if (self.tokenizer.peek()) |token2| {
                        if (is_amp_start(null, token2)) {
                            if (self.pop_amp_term()) |amp|
                                try n.line.append(amp);
                        }
                    }
                } else {
                    try n.line.append(self.pop_code_term() orelse unreachable);
                }
            } else {
                try n.line.append(self.pop_text_term() orelse unreachable);
            }
        }
    }

    fn pop_newline_term(self: *Self) ?Term {
        if (self.tokenizer.next()) |token| {
            if (token.symbol == tkn.Symbol.Newline)
                return Term{ .word = token.word, .kind = Term.Kind.Newline };
        }
        return null;
    }

    fn pop_amp_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            if (is_amp_start(null, first_token)) {
                // Savepoint to rollback to original state
                const sp_1 = self.tokenizer;

                var amp = Term{ .word = first_token.word, .kind = Term.Kind.Amp };
                self.tokenizer.commit_peek();

                // Savepoint to rollback to state before adding a ':'. This is used to avoid a trailing ':' in Amp.
                var sp_2: ?tkn.Tokenizer = null;

                while (self.tokenizer.peek()) |token| {
                    if (is_whitespace(token) or is_newline(token))
                        // We accept this Amp
                        break;

                    if (!is_amp_body(token)) {
                        // Restore the tokenizer: this is not an Amp
                        self.tokenizer = sp_1;
                        return null;
                    }

                    if (token.symbol == tkn.Symbol.Colon)
                        // Setup savepoint to support removing this ':' if it turns-out to be a trailing ':'
                        sp_2 = self.tokenizer
                    else
                        // Reset sp_2 (if any), this will accept the ':'
                        sp_2 = null;

                    self.tokenizer.commit_peek();
                    amp.word.len += token.word.len;
                }

                if (sp_2) |sp| {
                    self.tokenizer = sp;
                    if (self.tokenizer.peek()) |token|
                        amp.word.len -= token.word.len;
                }

                if (amp.word.len == first_token.word.len) {
                    // Do not accept an empty Amp
                    self.tokenizer = sp_1;
                    return null;
                }

                return amp;
            }
        }
        return null;
    }

    fn pop_text_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            var text = Term{ .word = first_token.word, .kind = Term.Kind.Text };
            self.tokenizer.commit_peek();

            while (self.tokenizer.peek()) |token| {
                if (is_newline(token) or is_amp_start(self.tokenizer.current(), token) or self.is_comment_start())
                    break;
                if (self.language == Language.Markdown and (token.symbol == tkn.Symbol.Backtick or token.symbol == tkn.Symbol.Dollar))
                    break;

                self.tokenizer.commit_peek();
                text.word.len += token.word.len;
            }
            return text;
        }
        return null;
    }

    fn pop_code_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            var code = Term{ .word = first_token.word, .kind = Term.Kind.Code };
            self.tokenizer.commit_peek();

            while (self.tokenizer.peek()) |token| {
                if (is_newline(token) or self.is_comment_start())
                    break;

                self.tokenizer.commit_peek();
                code.word.len += token.word.len;
            }
            return code;
        }
        return null;
    }

    fn pop_markdown_code_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            if (first_token.symbol != tkn.Symbol.Backtick)
                return null;

            var code = Term{ .word = first_token.word, .kind = Term.Kind.Code };
            self.tokenizer.commit_peek();

            while (self.tokenizer.next()) |token| {
                code.word.len += token.word.len;

                if (token.symbol == first_token.symbol and token.word.len == first_token.word.len)
                    break;
            }

            return code;
        }
        return null;
    }
    fn pop_markdown_formula_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            if (first_token.symbol != tkn.Symbol.Dollar)
                return null;

            var formula = Term{ .word = first_token.word, .kind = Term.Kind.Formula };
            self.tokenizer.commit_peek();

            while (self.tokenizer.next()) |token| {
                formula.word.len += token.word.len;

                if (token.symbol == first_token.symbol and token.word.len == first_token.word.len)
                    break;
            }

            return formula;
        }
        return null;
    }

    fn is_comment_start(self: *Self) bool {
        if (self.tokenizer.peek()) |first_token| {
            switch (self.language) {
                Language.Cish => {
                    if (first_token.symbol == tkn.Symbol.Slash and first_token.word.len >= 2)
                        return true;
                },
                Language.Ruby => {
                    if (first_token.symbol == tkn.Symbol.Hashtag)
                        return true;
                },
                Language.Markdown => {
                    if (first_token.symbol != tkn.Symbol.OpenAngle or first_token.word.len != 1)
                        return false;

                    const sp = self.tokenizer;
                    defer self.tokenizer = sp;

                    _ = self.tokenizer.next();

                    if (self.tokenizer.next()) |token| {
                        if (token.symbol != tkn.Symbol.Exclamation or token.word.len != 1)
                            return false;
                    }
                    if (self.tokenizer.next()) |token| {
                        if (token.symbol != tkn.Symbol.Minus or token.word.len < 2)
                            return false;
                    }

                    return true;
                },
                else => return false,
            }
        }
        return false;
    }

    fn pop_comment_start(self: *Self) ?Term {
        var maybe_sp: ?tkn.Tokenizer = self.tokenizer;

        if (self.tokenizer.next()) |first_token| {
            defer {
                if (maybe_sp) |sp| {
                    self.tokenizer = sp;
                }
            }

            var term = Term{ .word = first_token.word, .kind = Term.Kind.Comment };

            switch (self.language) {
                Language.Cish => {
                    if (first_token.symbol != tkn.Symbol.Slash or first_token.word.len < 2)
                        return null;
                },
                Language.Ruby => {
                    if (first_token.symbol != tkn.Symbol.Hashtag)
                        return null;
                },
                Language.Markdown => {
                    if (first_token.symbol != tkn.Symbol.OpenAngle or first_token.word.len != 1)
                        return null;
                    if (self.tokenizer.next()) |token| {
                        if (token.symbol != tkn.Symbol.Exclamation or token.word.len != 1) return null;
                        term.word.len += token.word.len;
                    }
                    if (self.tokenizer.next()) |token| {
                        if (token.symbol != tkn.Symbol.Minus or token.word.len < 2) return null;
                        term.word.len += token.word.len;
                    }
                },
                else => return null,
            }

            // Disable rollback
            maybe_sp = null;

            while (self.tokenizer.peek()) |token| {
                if (is_whitespace(token)) {
                    // We add whitespace to the comment start
                    self.tokenizer.commit_peek();
                    term.word.len += token.word.len;
                } else break;
            }

            return term;
        }
        return null;
    }

    fn pop_section_node(self: *Self) !?Node {
        if (self.tokenizer.peek()) |first_token| {
            if (is_title(first_token)) |my_depth| {
                var n = try self.pop_line() orelse unreachable;
                n.type = Node.Type.Section;

                while (self.tokenizer.peek()) |token| {
                    if (is_title(token)) |depth| {
                        if (depth <= my_depth)
                            // This is the start of a section with a depth too low: we cannot nest
                            break;
                        try n.push_child(try self.pop_section_node() orelse unreachable);
                    } else if (try self.pop_paragraph_node()) |p| {
                        try n.push_child(p);
                    } else if (try self.pop_bullets_node()) |p| {
                        try n.push_child(p);
                    } else break;
                }

                return n;
            }
        }
        return null;
    }

    fn pop_paragraph_node(self: *Self) !?Node {
        if (self.tokenizer.peek()) |first_token| {
            if (is_line(first_token)) {
                var n = try self.pop_line() orelse unreachable;
                n.type = Node.Type.Paragraph;

                while (try self.pop_bullets_node()) |p| {
                    try n.push_child(p);
                }
                return n;
            }
        }
        return null;
    }

    fn pop_bullets_node(self: *Self) !?Node {
        if (self.tokenizer.peek()) |first_token| {
            if (is_bullet(first_token)) |my_depth| {
                var n = try self.pop_line() orelse unreachable;
                n.type = Node.Type.Bullets;

                while (self.tokenizer.peek()) |token| {
                    if (is_bullet(token)) |depth| {
                        if (depth <= my_depth)
                            // This is the start of a section with a depth too low: we cannot nest
                            break;
                        try n.push_child(try self.pop_bullets_node() orelse unreachable);
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
    fn is_amp_start(maybe_past: ?tkn.Token, t: tkn.Token) bool {
        if (maybe_past) |past|
            if (!is_newline(past) and !is_whitespace(past))
                return false;
        return t.symbol == tkn.Symbol.Ampersand and t.word.len == 1;
    }
    fn is_amp_body(t: tkn.Token) bool {
        const S = tkn.Symbol;
        return t.symbol == S.Word or t.symbol == S.Underscore or t.symbol == S.Colon or t.symbol == S.Exclamation or t.symbol == S.Dot or t.symbol == S.Tilde;
    }
    fn is_whitespace(t: tkn.Token) bool {
        return t.symbol == tkn.Symbol.Space;
    }
    fn is_newline(t: tkn.Token) bool {
        return t.symbol == tkn.Symbol.Newline;
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
