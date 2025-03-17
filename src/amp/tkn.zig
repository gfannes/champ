const std = @import("std");
const ut = std.testing;

const Error = error{};

pub const Symbol = struct {
    pub const Kind = enum {
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

        pub fn new(ch: u8) ?Kind {
            // &perf: Use a lookup table?
            return switch (ch) {
                ' ' => Kind.Space,
                '!' => Kind.Exclamation,
                '?' => Kind.Questionmark,
                '|' => Kind.Pipe,
                '@' => Kind.At,
                '#' => Kind.Hashtag,
                '$' => Kind.Dollar,
                '%' => Kind.Percent,
                '^' => Kind.Hat,
                '&' => Kind.Ampersand,
                '*' => Kind.Star,
                '(' => Kind.OpenParens,
                ')' => Kind.CloseParens,
                '[' => Kind.OpenSquare,
                ']' => Kind.CloseSquare,
                '{' => Kind.OpenCurly,
                '}' => Kind.CloseCurly,
                '<' => Kind.OpenAngle,
                '>' => Kind.CloseAngle,
                '~' => Kind.Tilde,
                '+' => Kind.Plus,
                '-' => Kind.Minus,
                '=' => Kind.Equal,
                ':' => Kind.Colon,
                '_' => Kind.Underscore,
                '.' => Kind.Dot,
                ',' => Kind.Comma,
                ';' => Kind.Semicolon,
                '\'' => Kind.SingleQuote,
                '"' => Kind.DoubleQuote,
                '`' => Kind.Backtick,
                '/' => Kind.Slash,
                '\\' => Kind.BackSlash,
                '\n' => Kind.Newline,
                '\r' => Kind.CarriageReturn,
                else => return null,
            };
        }
    };

    kind: Kind,
    count: usize,
};

pub const Token = union(enum) {
    symbol: Symbol,
    word: []const u8,
};

pub const Tokens = struct {
    const _Tokens = std.ArrayList(Token);
    const _Content = std.ArrayList(u8);

    content: []const u8 = &.{},

    _content: _Content,
    _tokens: _Tokens,
    _content_ix: usize = 0,
    _current_token: ?Token = null,

    _ma: std.mem.Allocator,

    pub fn init(ma: std.mem.Allocator) Tokens {
        return Tokens{ ._content = _Content.init(ma), ._tokens = _Tokens.init(ma), ._ma = ma };
    }
    pub fn deinit(self: *Tokens) void {
        self._content.deinit();
        self._tokens.deinit();
    }

    pub fn alloc_content(self: *Tokens, size: usize) ![]u8 {
        try self._content.resize(size);
        self.content = self._content.items;
        try self._tokens.resize(0);
        return self._content.items;
    }

    pub fn scan(self: *Tokens) !void {
        self._content_ix = 0;

        for (self.content) |ch| {
            if (Symbol.Kind.new(ch)) |symbol_kind|
                try self._symbol(symbol_kind)
            else
                try self._letter();
            self._content_ix += 1;
        }

        if (self._current_token) |*token| {
            try self._tokens.append(token.*);
            self._current_token = null;
        }
    }

    fn _symbol(self: *Tokens, kind: Symbol.Kind) !void {
        if (self._current_token) |*token| {
            switch (token.*) {
                .symbol => |*symbol| {
                    if (symbol.kind == kind) {
                        symbol.count += 1;
                        return;
                    }
                },
                else => {},
            }
            // We could not merge 'kind' into token: finish current token and create a new one hereunder
            try self._tokens.append(token.*);
        }
        self._current_token = Token{ .symbol = Symbol{ .kind = kind, .count = 1 } };
    }

    fn _letter(self: *Tokens) !void {
        if (self._current_token) |*token| {
            switch (token.*) {
                .word => |*word| {
                    word.len += 1;
                    return;
                },
                else => {},
            }
            // We could not merge letter into token: finish current token and create a new one hereunder
            try self._tokens.append(token.*);
        }
        self._current_token = Token{ .word = self.content[self._content_ix .. self._content_ix + 1] };
    }
};

test {
    const ma = ut.allocator;

    var tokens = Tokens.init(ma);
    defer tokens.deinit();

    const content = "# Title\n\n## Subtitle\n\nText\n\n- Bullet1\n- Bullet2\n  - Bullet2";
    std.mem.copyForwards(u8, try tokens.alloc_content(content.len), content);

    try tokens.scan();

    for (tokens._tokens.items) |token| {
        switch (token) {
            .symbol => |s| std.debug.print("Symbol: {} {}\n", .{ s.count, s.kind }),
            .word => |w| std.debug.print("Word: '{s}'\n", .{w}),
        }
    }
}
