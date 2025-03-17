const std = @import("std");
const ut = std.testing;

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

pub const Token = struct {
    // Note: using u32 for ix/len is slightly faster (487ms vs 490ms): not worth it
    word: []const u8,
    symbol: Symbol,
};

pub const Tokenizer = struct {
    const Tokens = std.ArrayList(Token);
    const String = std.ArrayList(u8);

    tokens: Tokens,
    content: String,

    pub fn init(ma: std.mem.Allocator) Tokenizer {
        return Tokenizer{ .content = String.init(ma), .tokens = Tokens.init(ma) };
    }
    pub fn deinit(self: *Tokenizer) void {
        self.content.deinit();
        self.tokens.deinit();
    }

    // Resizes internal buffer to requested size and provides read access to it
    pub fn alloc_content(self: *Tokenizer, size: usize) ![]u8 {
        try self.tokens.resize(0);
        try self.content.resize(size);
        return self.content.items;
    }

    pub fn scan(self: *Tokenizer) !void {
        const content: []const u8 = self.content.items;

        if (content.len == 0)
            // Nothing to do
            return;

        // Setup current_token to ensure it matches with the first characeter in below's loop
        var current_token = Token{ .word = content[0..0], .symbol = Symbol.from(content[0]) };

        for (content, 0..) |ch, ix| {
            const symbol = Symbol.from(ch);

            if (current_token.symbol != symbol) {
                try self.tokens.append(current_token);
                current_token = Token{ .word = content[ix..ix], .symbol = symbol };
            }

            current_token.word.len += 1;
        }

        // Push last 'current_token'
        try self.tokens.append(current_token);
    }
};

test {
    var tokens = Tokenizer.init(ut.allocator);
    defer tokens.deinit();

    const content = "# Title\n\n## Subtitle\n\nText\n\n- Bullet1\n- Bullet2\n  - Bullet2";
    std.mem.copyForwards(u8, try tokens.alloc_content(content.len), content);

    try tokens.scan();

    for (tokens.tokens.items) |token| {
        std.debug.print("Token: symbol {} word {s}\n", .{ token.symbol, token.word });
    }
}
