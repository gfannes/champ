const std = @import("std");

const naft = @import("rubr").naft;

const tkn = @import("../tkn.zig");

const dto = @import("dto.zig");
const Language = dto.Language;
const Node = dto.Node;
const Tree = dto.Tree;
const Term = dto.Term;
const Line = dto.Line;
const Terms = dto.Terms;

pub const Error = error{
    UnexpectedState,
    CouldNotParse,
    ExpectedLanguage,
};

// &rework: Split pop_txt_X(), pop_md_X() and pop_nonmd_X() into different structs and maybe files
// &todo: Add UTs for all different conditions
pub const Parser = struct {
    const Self = @This();
    const Strings = std.ArrayList([]const u8);

    root_id: Tree.Id,
    tree: *Tree,
    language: Language,
    tokenizer: tkn.Tokenizer,
    a: std.mem.Allocator,

    pub fn init(root_id: Tree.Id, tree: *Tree, a: std.mem.Allocator) !Self {
        const r = tree.ptr(root_id);
        const language = r.language orelse return Error.ExpectedLanguage;
        return Self{
            .root_id = root_id,
            .tree = tree,
            .language = language,
            .tokenizer = tkn.Tokenizer.init(r.content),
            .a = a,
        };
    }
    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn parse(self: *Self) !void {
        switch (self.language) {
            Language.Markdown => while (true) {
                if (try self.pop_section_node(self.root_id)) {} else if (try self.pop_paragraph_node(self.root_id)) {} else if (try self.pop_bullets_node(self.root_id)) {} else {
                    break;
                }
            },
            else => while (true) {
                if (try self.pop_line()) |line| {
                    const entry = try self.tree.addChild(self.root_id);
                    entry.data.* = line;
                } else break;
            },
        }
    }

    fn pop_line(self: *Self) !?Node {
        if (self.tokenizer.empty())
            return null;

        var n = Node.init(self.a);
        errdefer n.deinit();

        switch (self.language) {
            Language.Markdown => try self.pop_md_text(&n),
            Language.Text => try self.pop_txt_text(&n),
            Language.Cish, Language.Ruby, Language.Lua => try self.pop_nonmd_code_comment_text(&n),
        }

        return n;
    }

    fn appendToLine(self: *Self, n: *Node, term: Term) !void {
        try n.line.append(term, &self.root().terms);
    }

    fn pop_md_text(self: *Self, n: *Node) !void {
        var text = struct {
            const My = @This();

            outer: *Self,
            n: *Node,
            maybe_text: ?Term = null,

            fn commit(my: *My) !void {
                if (my.maybe_text) |text| {
                    try my.outer.appendToLine(my.n, text);
                    my.maybe_text = null;
                }
            }
            fn push(my: *My, token: tkn.Token) void {
                if (my.maybe_text) |*text|
                    text.word.len += token.word.len
                else
                    my.maybe_text = Term{ .word = token.word, .kind = Term.Kind.Text };
            }
        }{ .outer = self, .n = n };

        while (self.tokenizer.peek()) |token| {
            if (is_newline(token)) {
                try text.commit();
                try self.appendToLine(n, self.pop_newline_term() orelse unreachable);
                return;
            }

            if (is_amp_start(self.tokenizer.current(), token)) {
                if (self.pop_amp_term()) |amp| {
                    try text.commit();
                    try self.appendToLine(n, amp);
                    continue;
                }
            }
            if (self.pop_md_code_term()) |code| {
                try text.commit();
                try self.appendToLine(n, code);
                continue;
            }
            if (self.pop_md_formula_term()) |formula| {
                try text.commit();
                try self.appendToLine(n, formula);
                continue;
            }
            if (self.pop_md_comment_start()) |comment_start| {
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

                try text.commit();
                try self.appendToLine(n, comment);
                continue;
            }

            text.push(token);
            self.tokenizer.commit_peek();
        }

        try text.commit();
    }

    fn pop_txt_text(self: *Self, n: *Node) !void {
        while (self.tokenizer.peek()) |token| {
            if (is_amp_start(self.tokenizer.current(), token)) {
                if (self.pop_amp_term()) |amp| {
                    try self.appendToLine(n, amp);
                    continue;
                }
            }

            // If token is '&' but above could not pop a real Amp, make sure we will pop a Text
            const accept_inital_amp = true;
            if (self.pop_txt_text_term(accept_inital_amp)) |text| {
                try self.appendToLine(n, text);
                continue;
            }

            if (self.pop_newline_term()) |newline| {
                try self.appendToLine(n, newline);
                break;
            }

            std.debug.print("Unexpected token for txt '{s}'\n", .{token.word});
            return Error.CouldNotParse;
        }
    }

    // &todo: handle multiline comments
    fn pop_nonmd_code_comment_text(self: *Self, n: *Node) !void {
        var found_comment = false;
        while (true) {
            if (!found_comment) {
                if (self.pop_nonmd_comment_term()) |comment| {
                    try self.appendToLine(n, comment);
                    found_comment = true;

                    // For now, we merge all Amps and Whitespaces
                    // &multiamp &todo Add seperate Amps
                    var maybe_term: ?dto.Term = null;
                    while (self.pop_amp_term()) |amp| {
                        if (maybe_term) |*term| {
                            term.word.len += amp.word.len;
                        } else {
                            maybe_term = amp;
                        }

                        if (self.pop_nonmd_whitespace_term()) |whitespace|
                            (maybe_term orelse unreachable).word.len += whitespace.word.len;
                    }

                    if (maybe_term) |term|
                        try self.appendToLine(n, term);

                    continue;
                }
                if (self.pop_nonmd_code_term()) |code| {
                    try self.appendToLine(n, code);
                    continue;
                }
            } else if (self.pop_nonmd_text_term()) |text| {
                try self.appendToLine(n, text);
                continue;
            }

            if (self.pop_newline_term()) |newline| {
                try self.appendToLine(n, newline);
                break;
            }

            // This point should only be reached when everything is parsed
            if (self.tokenizer.peek()) |token| {
                std.debug.print("Unexpected token for nonmd '{s}'\n", .{token.word});
                return Error.CouldNotParse;
            } else break;
        }
    }

    fn pop_newline_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |token| {
            if (is_newline(token)) {
                self.tokenizer.commit_peek();
                return Term{ .word = token.word, .kind = Term.Kind.Newline };
            }
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

    // Only called after Comment and potentially Amp was already found
    fn pop_nonmd_text_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            if (is_newline(first_token))
                return null;

            var text = Term{ .word = first_token.word, .kind = Term.Kind.Text };
            self.tokenizer.commit_peek();

            while (self.tokenizer.peek()) |token| {
                if (is_newline(token))
                    break;

                self.tokenizer.commit_peek();
                text.word.len += token.word.len;
            }
            return text;
        }
        return null;
    }

    fn pop_txt_text_term(self: *Self, accept_initial_amp: bool) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            if (is_newline(first_token) or (!accept_initial_amp and is_amp_start(self.tokenizer.current(), first_token)))
                return null;

            var text = Term{ .word = first_token.word, .kind = Term.Kind.Text };
            self.tokenizer.commit_peek();

            while (self.tokenizer.peek()) |token| {
                if (is_newline(token) or is_amp_start(self.tokenizer.current(), token))
                    break;

                self.tokenizer.commit_peek();
                text.word.len += token.word.len;
            }
            return text;
        }
        return null;
    }

    fn pop_nonmd_comment_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            if (!is_comment(first_token, self.language))
                return null;

            var comment = Term{ .word = first_token.word, .kind = Term.Kind.Comment };
            self.tokenizer.commit_peek();

            while (self.tokenizer.peek()) |token| {
                if (is_whitespace(token)) {
                    // We add whitespace to the comment start
                    self.tokenizer.commit_peek();
                    comment.word.len += token.word.len;
                } else break;
            }

            return comment;
        }
        return null;
    }

    fn pop_nonmd_whitespace_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            if (!is_whitespace(first_token))
                return null;

            var whitespace = Term{ .word = first_token.word, .kind = Term.Kind.Whitespace };
            self.tokenizer.commit_peek();

            while (self.tokenizer.peek()) |token| {
                if (is_whitespace(token)) {
                    self.tokenizer.commit_peek();
                    whitespace.word.len += token.word.len;
                } else break;
            }

            return whitespace;
        }
        return null;
    }

    fn pop_nonmd_code_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            if (is_newline(first_token) or is_comment(first_token, self.language))
                return null;

            var code = Term{ .word = first_token.word, .kind = Term.Kind.Code };
            self.tokenizer.commit_peek();

            while (self.tokenizer.peek()) |token| {
                if (is_newline(token) or is_comment(token, self.language))
                    break;

                self.tokenizer.commit_peek();
                code.word.len += token.word.len;
            }
            return code;
        }
        return null;
    }

    fn pop_md_code_term(self: *Self) ?Term {
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
    fn pop_md_formula_term(self: *Self) ?Term {
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

    fn pop_md_comment_start(self: *Self) ?Term {
        std.debug.assert(self.language == Language.Markdown);

        // We look for '<!--'

        if (self.tokenizer.peek()) |first_token| {
            // Is this '<'?
            if (first_token.symbol != tkn.Symbol.OpenAngle or first_token.word.len != 1)
                return null;

            // Setup rollback
            var maybe_sp: ?tkn.Tokenizer = self.tokenizer;
            defer {
                if (maybe_sp) |sp| {
                    self.tokenizer = sp;
                }
            }

            var comment_start = Term{ .word = first_token.word, .kind = Term.Kind.Comment };
            self.tokenizer.commit_peek();

            if (self.tokenizer.next()) |token| {
                // Is this '!'?
                if (token.symbol != tkn.Symbol.Exclamation or token.word.len != 1)
                    return null;
                comment_start.word.len += token.word.len;
            }
            if (self.tokenizer.next()) |token| {
                // Is this '--'?
                if (token.symbol != tkn.Symbol.Minus or token.word.len < 2)
                    return null;
                comment_start.word.len += token.word.len;
            }

            // Disable rollback
            maybe_sp = null;

            // We include any additional whitespace into the comment_start
            while (self.tokenizer.peek()) |token| {
                if (is_whitespace(token)) {
                    // We add whitespace to the comment start
                    self.tokenizer.commit_peek();
                    comment_start.word.len += token.word.len;
                } else break;
            }

            return comment_start;
        }

        return null;
    }

    fn pop_section_node(self: *Self, parent_id: Tree.Id) !bool {
        if (self.tokenizer.peek()) |first_token| {
            if (is_title(first_token)) |my_depth| {
                const entry = try self.tree.addChild(parent_id);
                const n = entry.data;
                n.* = try self.pop_line() orelse unreachable;
                n.type = Node.Type.Section;

                while (self.tokenizer.peek()) |token| {
                    if (is_title(token)) |depth| {
                        if (depth <= my_depth)
                            // This is the start of a section with a depth too low: we cannot nest
                            break;
                        std.debug.assert(try self.pop_section_node(entry.id));
                    } else if (try self.pop_paragraph_node(entry.id)) {} else if (try self.pop_bullets_node(entry.id)) {} else break;
                }

                return true;
            }
        }
        return false;
    }

    fn pop_paragraph_node(self: *Self, parent_id: Tree.Id) !bool {
        if (self.tokenizer.peek()) |first_token| {
            if (is_line(first_token)) {
                const entry = try self.tree.addChild(parent_id);
                const n = entry.data;
                n.* = try self.pop_line() orelse unreachable;
                n.type = Node.Type.Paragraph;

                while (try self.pop_bullets_node(entry.id)) {}
                return true;
            }
        }
        return false;
    }

    fn pop_bullets_node(self: *Self, parent_id: Tree.Id) !bool {
        if (self.tokenizer.peek()) |first_token| {
            if (is_bullet(first_token)) |my_depth| {
                const entry = try self.tree.addChild(parent_id);
                const n = entry.data;
                n.* = try self.pop_line() orelse unreachable;
                n.type = Node.Type.Bullets;

                while (self.tokenizer.peek()) |token| {
                    if (is_bullet(token)) |depth| {
                        if (depth <= my_depth)
                            // This is the start of a section with a depth too low: we cannot nest
                            break;
                        std.debug.assert(try self.pop_bullets_node(entry.id));
                    } else break;
                }
                return true;
            }
        }
        return false;
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
            Language.Cish => t.symbol == tkn.Symbol.Slash and t.word.len >= 2,
            Language.Ruby => t.symbol == tkn.Symbol.Hashtag,
            Language.Lua => t.symbol == tkn.Symbol.Minus and t.word.len >= 2,
            else => false,
        };
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

    fn root(self: *Self) *Node {
        return self.tree.ptr(self.root_id);
    }
};

test "Parser.parse()" {
    const ut = std.testing;

    {
        const content = "# Title1\n\n## Section\n\nLine\n- Bullet\n# Title2\nLine\n# Title3\n - Bullet\nLine\n# Title 4\n- b\n - bb\n- c";

        var parser = try Parser.init("path", Language.Markdown, content, ut.allocator);

        var file = try parser.parse();
        defer file.deinit();

        var n = naft.Node.init(null);
        file.write(&n);
    }
    {
        const content = "#include <iostream>\nint main(){\n  std::cout << \"Hello world.\" << std::endl; // &todo: place real program here\nreturn 0;\n}";

        var parser = try Parser.init("path", Language.Cish, content, ut.allocator);

        var file = try parser.parse();
        defer file.deinit();

        var n = naft.Node.init(null);
        file.write(&n);
    }
}
