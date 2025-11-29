const std = @import("std");

const rubr = @import("rubr");
const naft = rubr.naft;

const tkn = @import("../tkn.zig");
const Status = @import("../amp.zig").Status;

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

    a: std.mem.Allocator,

    root_id: Tree.Id,
    tree: *Tree,
    language: Language,
    content: []const u8,
    path: []const u8,
    tokenizer: tkn.Tokenizer,

    pub fn init(a: std.mem.Allocator, root_id: Tree.Id, tree: *Tree) !Self {
        const r = tree.ptr(root_id);
        const language = r.language orelse return Error.ExpectedLanguage;
        return Self{
            .a = a,
            .root_id = root_id,
            .tree = tree,
            .language = language,
            .content = r.content,
            .path = r.path,
            .tokenizer = tkn.Tokenizer.init(r.content),
        };
    }

    pub fn parse(self: *Self) !void {
        switch (self.language) {
            Language.Markdown => while (true) {
                if (try self.pop_section_node(self.root_id))
                    continue;
                if (try self.pop_paragraph_node(self.root_id))
                    continue;
                if (try self.pop_bullets_node(self.root_id))
                    continue;

                break;
            },
            else => while (true) {
                if (try self.pop_line()) |line| {
                    const entry = try self.tree.addChild(self.root_id);
                    entry.data.* = line;
                    continue;
                }

                break;
            },
        }

        var cb = struct {
            const My = @This();

            terms: []const Term,
            row: usize = 0,
            col: usize = 0,

            pub fn call(my: *My, entry: Tree.Entry) !void {
                const n = entry.data;
                n.content_rows.begin = my.row;
                n.content_cols.begin = my.col;
                for (n.line.terms_ixr.begin..n.line.terms_ixr.end) |term_ix| {
                    const term = &my.terms[term_ix];
                    switch (term.kind) {
                        Term.Kind.Newline => {
                            my.row += term.word.len;
                            my.col = 0;
                        },
                        else => {
                            my.col += term.word.len;

                            // We update content_rows/content_cols here and not after this for loop
                            // to not include the last Newline
                            n.content_rows.end = my.row;
                            n.content_cols.end = my.col;
                        },
                    }
                }
            }
        }{ .terms = self.root().terms.items };
        try self.tree.dfs(self.root_id, true, &cb);
    }

    fn pop_line(self: *Self) !?Node {
        const first_token = self.tokenizer.peek() orelse return null;
        var content = first_token.word;

        var n = Node{ .a = self.a };
        errdefer n.deinit();
        n.type = Node.Type.Line;

        switch (self.language) {
            Language.Markdown => try self.pop_md_text(&n),
            Language.Text => try self.pop_txt_text(&n),
            Language.Cish, Language.Ruby, Language.Python, Language.Lua => try self.pop_nonmd_code_comment_text(&n),
        }

        if (self.tokenizer.peek()) |last_token| {
            content.len = last_token.word.ptr - content.ptr;
        } else {
            const start_offset: usize = content.ptr - self.content.ptr;
            content.len = self.content.len - start_offset;
        }

        // Strip leading/trailing whitespace and newlines
        while (content.len > 0) {
            switch (content[0]) {
                '\n', '\r', ' ', '\t' => {
                    content.ptr += 1;
                    content.len -= 1;
                },
                else => break,
            }
        }
        while (content.len > 0) {
            switch (content[content.len - 1]) {
                '\n', '\r', ' ', '\t' => content.len -= 1,
                else => break,
            }
        }

        n.content = content;
        n.path = self.path;

        return n;
    }

    fn appendToLine(self: *Self, n: *Node, term: Term) !void {
        try n.line.append(term, &self.root().terms, self.a);
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

        var check_for_bullet: bool = true;

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
            if (check_for_bullet) {
                check_for_bullet = false;
                if (self.pop_md_bullet_term()) |bullet| {
                    try text.commit();
                    try self.appendToLine(n, bullet);
                    if (self.pop_md_checkbox_term()) |checkbox| {
                        try text.commit();
                        try self.appendToLine(n, checkbox);
                    }
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
            if (self.pop_capital_term()) |capital| {
                try text.commit();
                try self.appendToLine(n, capital);
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

            if (self.pop_capital_term()) |capital| {
                try self.appendToLine(n, capital);
                continue;
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

                    while (self.pop_amp_term()) |amp| {
                        try self.appendToLine(n, amp);

                        if (self.pop_nonmd_whitespace_term()) |whitespace|
                            try self.appendToLine(n, whitespace);
                    }

                    continue;
                }
                if (self.pop_nonmd_code_term()) |code| {
                    try self.appendToLine(n, code);
                    continue;
                }
            } else if (self.pop_capital_term()) |capital| {
                try self.appendToLine(n, capital);
                continue;
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

                // Savepoint to rollback to state before adding a '[:.]'. This is used to avoid a trailing '[:.]' in Amp.
                var sp_2: ?tkn.Tokenizer = null;

                while (self.tokenizer.peek()) |token| {
                    if (is_whitespace(token) or is_newline(token) or is_questionmark(token) or is_exclamation(token))
                        // We accept this Amp
                        break;

                    if (!is_amp_body(token)) {
                        // Restore the tokenizer: this is not an Amp
                        self.tokenizer = sp_1;
                        return null;
                    }

                    if (token.symbol == tkn.Symbol.Colon or token.symbol == tkn.Symbol.Dot)
                        // Setup savepoint to support removing this '[:.]' if it turns-out to be a trailing '[:.]'
                        sp_2 = self.tokenizer
                    else
                        // Reset sp_2 (if any), this will accept the '[:.]'
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

    fn pop_md_bullet_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            if (is_bullet(first_token) == null)
                return null;

            var bullet = Term{ .word = first_token.word, .kind = Term.Kind.Bullet };
            self.tokenizer.commit_peek();

            while (self.tokenizer.peek()) |token| {
                switch (token.symbol) {
                    tkn.Symbol.Space, tkn.Symbol.Tab, tkn.Symbol.Minus, tkn.Symbol.Star => {
                        bullet.word.len += token.word.len;
                        self.tokenizer.commit_peek();
                    },
                    else => break,
                }
            }

            return bullet;
        }
        return null;
    }
    fn pop_md_checkbox_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |first_token| {
            if (first_token.symbol != tkn.Symbol.OpenSquare or first_token.word.len != 1)
                return null;

            // Popping this checkbox might still fail if it contains more or less that 1 char
            const sp = self.tokenizer;

            var checkbox = Term{ .word = first_token.word, .kind = Term.Kind.Checkbox };
            self.tokenizer.commit_peek();

            if (self.tokenizer.next()) |middle_tkn| {
                if (middle_tkn.symbol != tkn.Symbol.CloseSquare and middle_tkn.word.len == 1) {
                    checkbox.word.len += middle_tkn.word.len;
                    if (self.tokenizer.next()) |last_tkn| {
                        if (last_tkn.symbol == tkn.Symbol.CloseSquare and last_tkn.word.len == 1) {
                            checkbox.word.len += last_tkn.word.len;
                            return checkbox;
                        }
                    }
                }
            }

            self.tokenizer = sp;
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
        // Savepoint to rollback to original state.
        const sp = self.tokenizer;

        if (self.tokenizer.peek()) |first_token| {
            if (first_token.symbol != tkn.Symbol.Dollar)
                return null;

            var formula = Term{ .word = first_token.word, .kind = Term.Kind.Formula };
            self.tokenizer.commit_peek();

            while (self.tokenizer.next()) |token| {
                formula.word.len += token.word.len;

                if (token.symbol == tkn.Symbol.Newline and first_token.word.len == 1) {
                    // This is an unclosed inline formula: do not detect it.
                    self.tokenizer = sp;
                    return null;
                }

                if (token.symbol == first_token.symbol and token.word.len == first_token.word.len)
                    break;
            }

            return formula;
        }

        return null;
    }
    fn pop_capital_term(self: *Self) ?Term {
        if (self.tokenizer.peek()) |token| {
            if (token.symbol != tkn.Symbol.Word)
                return null;
            if (Status.fromCapital(token.word) == null)
                return null;

            const capital = Term{ .word = token.word, .kind = Term.Kind.Capital };
            self.tokenizer.commit_peek();

            return capital;
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
                n.type = Node.Type.Bullet;

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
        return if (t.symbol == tkn.Symbol.Space or t.symbol == tkn.Symbol.Tab)
            t.word.len
        else if (t.symbol == tkn.Symbol.Minus or t.symbol == tkn.Symbol.Star)
            0
        else
            null;
    }
    fn is_comment(t: tkn.Token, language: Language) bool {
        return switch (language) {
            Language.Cish => t.symbol == tkn.Symbol.Slash and t.word.len >= 2,
            Language.Ruby, Language.Python => t.symbol == tkn.Symbol.Hashtag,
            Language.Lua => t.symbol == tkn.Symbol.Minus and t.word.len >= 2,
            else => false,
        };
    }
    fn is_amp_start(maybe_past: ?tkn.Token, t: tkn.Token) bool {
        if (maybe_past) |past|
            if (!is_newline(past) and !is_whitespace(past))
                return false;
        return t.symbol == tkn.Symbol.Ampersand;
    }
    fn is_amp_body(t: tkn.Token) bool {
        const S = tkn.Symbol;
        return t.symbol == S.Word or t.symbol == S.Underscore or t.symbol == S.Colon or t.symbol == S.Ampersand or t.symbol == S.Dot or t.symbol == S.Tilde;
    }
    fn is_whitespace(t: tkn.Token) bool {
        return t.symbol == tkn.Symbol.Space;
    }
    fn is_newline(t: tkn.Token) bool {
        return t.symbol == tkn.Symbol.Newline;
    }
    fn is_questionmark(t: tkn.Token) bool {
        return t.symbol == tkn.Symbol.Questionmark;
    }
    fn is_exclamation(t: tkn.Token) bool {
        return t.symbol == tkn.Symbol.Exclamation;
    }

    fn root(self: *Self) *Node {
        return self.tree.ptr(self.root_id);
    }
};

test "Parser.parse()" {
    const ut = std.testing;

    var aral = std.heap.ArenaAllocator.init(ut.allocator);
    defer aral.deinit();
    const aa = aral.allocator();

    var tree = Tree.init(ut.allocator);
    defer {
        for (tree.nodes.items) |*node|
            node.data.deinit();
        tree.deinit();
    }

    const Scn = struct { content: []const u8, language: Language };
    for (&[_]Scn{
        Scn{
            .content = "# Title1\n\n## Section\n\nLine\n- Bullet\n# Title2\nLine\n# Title3\n - Bullet\nLine\n# Title 4\n- b\n - bb\n- c",
            .language = Language.Markdown,
        },
        Scn{
            .content = "#include <iostream>\nint main(){\n  std::cout << \"Hello world.\" << std::endl; // &todo: place real program here\nreturn 0;\n}",
            .language = Language.Cish,
        },
    }) |scn| {
        const f = try tree.addChild(null);
        const n = f.data;
        n.* = Node{ .a = ut.allocator };
        n.content = try aa.dupe(u8, scn.content);
        n.language = scn.language;

        var parser = try Parser.init(f.id, &tree, ut.allocator);

        try parser.parse();
    }
}
