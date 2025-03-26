const std = @import("std");
const ut = std.testing;

pub const Token = struct {
    // Note: using u32 for ix/len is slightly faster (487ms vs 490ms): not worth it
    word: []const u8,
    symbol: Symbol,
};

pub const Tokenizer = struct {
    pub const Tokens = std.ArrayList(Token);
    const Self = @This();

    content: []const u8,

    // Single future token to support peek()
    peek_token: ?Token = null,
    // Last token emitted from next() to supports current()
    current_token: ?Token = null,

    pub fn init(content: []const u8) Self {
        return Self{ .content = content };
    }

    // 460ms
    pub fn scan(self: *Self, tokens: *Tokens) !void {
        try tokens.resize(0);

        if (self.content.len == 0)
            // Nothing to do
            return;

        // Setup current_token to ensure it matches with the first characeter in below's loop
        var current_token = Token{ .word = self.content[0..0], .symbol = Symbol.from(self.content[0]) };

        for (self.content, 0..) |ch, ix| {
            const symbol = Symbol.from(ch);

            if (current_token.symbol != symbol) {
                try tokens.append(current_token);
                current_token = Token{ .word = self.content[ix..ix], .symbol = symbol };
            }

            current_token.word.len += 1;
        }

        // Push last 'current_token'
        try tokens.append(current_token);

        // Consume all content
        self.content.ptr += self.content.len;
        self.content.len = 0;
    }

    pub fn next(self: *Self) ?Token {
        if (self.peek_token == null)
            self.current_token = self.next_()
        else
            self.commit_peek();
        return self.current_token;
    }

    pub fn peek(self: *Self) ?Token {
        if (self.peek_token == null)
            self.peek_token = self.next_();
        return self.peek_token;
    }

    pub fn current(self: *Self) ?Token {
        return self.current_token;
    }

    pub fn commit_peek(self: *Self) void {
        self.current_token = self.peek_token;
        self.peek_token = null;
    }

    pub fn empty(self: *Self) bool {
        if (self.peek_token == null)
            self.peek_token = self.next_();
        return self.peek_token == null;
    }

    // &perf: It might be faster to prepare a few tokens and cache them
    // 355ms
    fn next_(self: *Self) ?Token {
        // Note: storing a local Token and returning ?*Token is slower
        var maybe_token: ?Token = null;

        for (self.content, 0..) |ch, ix| {
            const symbol = Symbol.from(ch);
            if (maybe_token) |*token| {
                if (symbol != token.symbol) {
                    token.word.len = ix;
                    self.content.ptr += token.word.len;
                    self.content.len -= token.word.len;
                    return maybe_token;
                }
            } else {
                // Init maybe_token to contain all remaining content
                maybe_token = Token{ .word = self.content, .symbol = symbol };
            }
        }

        // We found a match until the end: consume all content
        self.content.ptr += self.content.len;
        self.content.len = 0;

        return maybe_token;
    }
};

// &perf: Reducing the Symbols to only those needed will result in larger Tokens and thus less iterations
pub const Symbol = enum(u8) {
    Word,

    Space,
    Exclamation,
    Questionmark,
    Pipe,
    At,
    Hashtag,
    Dollar,
    Percent,
    Hat,
    Ampersand,
    Star,
    OpenParens,
    CloseParens,
    OpenSquare,
    CloseSquare,
    OpenCurly,
    CloseCurly,
    OpenAngle,
    CloseAngle,
    Tilde,
    Plus,
    Minus,
    Equal,
    Colon,
    Underscore,
    Dot,
    Comma,
    Semicolon,
    SingleQuote,
    DoubleQuote,
    Backtick,
    Slash,
    BackSlash,
    Newline,
    CarriageReturn,

    pub fn from(ch: u8) Symbol {
        return ch__symbol[ch];
    }
};

const ch__symbol: [256]Symbol = blk: {
    var t = [_]Symbol{Symbol.Word} ** 256;

    t[' '] = Symbol.Space;
    t['!'] = Symbol.Exclamation;
    t['?'] = Symbol.Questionmark;
    t['|'] = Symbol.Pipe;
    t['@'] = Symbol.At;
    t['#'] = Symbol.Hashtag;
    t['$'] = Symbol.Dollar;
    t['%'] = Symbol.Percent;
    t['^'] = Symbol.Hat;
    t['&'] = Symbol.Ampersand;
    t['*'] = Symbol.Star;
    t['('] = Symbol.OpenParens;
    t[')'] = Symbol.CloseParens;
    t['['] = Symbol.OpenSquare;
    t[']'] = Symbol.CloseSquare;
    t['{'] = Symbol.OpenCurly;
    t['}'] = Symbol.CloseCurly;
    t['<'] = Symbol.OpenAngle;
    t['>'] = Symbol.CloseAngle;
    t['~'] = Symbol.Tilde;
    t['+'] = Symbol.Plus;
    t['-'] = Symbol.Minus;
    t['='] = Symbol.Equal;
    t[':'] = Symbol.Colon;
    t['_'] = Symbol.Underscore;
    t['.'] = Symbol.Dot;
    t[','] = Symbol.Comma;
    t[';'] = Symbol.Semicolon;
    t['\''] = Symbol.SingleQuote;
    t['"'] = Symbol.DoubleQuote;
    t['`'] = Symbol.Backtick;
    t['/'] = Symbol.Slash;
    t['\\'] = Symbol.BackSlash;
    t['\n'] = Symbol.Newline;
    t['\r'] = Symbol.CarriageReturn;

    break :blk t;
};

test "Tokenizer.scan()" {
    const content = "# Title\n\n## Subtitle\n\nText\n\n- Bullet1\n- Bullet2\n  - Bullet2";

    var tokenizer = Tokenizer.init(content);

    var tokens = Tokenizer.Tokens.init(ut.allocator);
    defer tokens.deinit();

    try tokenizer.scan(&tokens);

    for (tokens.items) |token| {
        std.debug.print("Token: symbol {} word {s}\n", .{ token.symbol, token.word });
    }
}

test "Tokenizer.next()" {
    const content = "# Title\n\n## Subtitle\n\nText\n\n- Bullet1\n- Bullet2\n  - Bullet2";

    var tokenizer = Tokenizer.init(content);

    while (tokenizer.next()) |token| {
        std.debug.print("Token: symbol {} word {s}\n", .{ token.symbol, token.word });
    }
}
