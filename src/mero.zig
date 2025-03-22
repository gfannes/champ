const std = @import("std");
const ut = std.testing;

const naft = @import("rubr").naft;

const tkn = @import("tkn.zig");

pub const Token = struct {
    const Self = @This();
    pub const Kind = enum {
        Text,
        Amp,
    };

    word: []const u8,
    kind: Kind,

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Token");
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
    const Tokens = std.ArrayList(Token);

    tokens: Tokens,

    pub fn init(ma: std.mem.Allocator) Line {
        return Self{ .tokens = Tokens.init(ma) };
    }
    pub fn deinit(self: *Self) void {
        self.tokens.deinit();
    }

    pub fn append(self: *Self, word: []const u8, kind: Token.Kind) !void {
        try self.tokens.append(Token{ .word = word, .kind = kind });
    }

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Line");
        defer n.deinit();
        for (self.tokens.items) |token| {
            if (token.word.len > 0 and token.word[0] != '\n')
                n.text(token.word);
        }
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

pub const Parser = struct {
    const Self = @This();
    const Strings = std.ArrayList([]const u8);

    ma: std.mem.Allocator,
    next_token: ?tkn.Token = null,

    tokenizer: tkn.Tokenizer = undefined,

    pub fn init(ma: std.mem.Allocator) Self {
        return Self{ .ma = ma };
    }

    pub fn parse(self: *Self, content: []const u8) !Node {
        var root = Node.init(self.ma);
        root.type = Node.Type.Root;

        self.tokenizer = tkn.Tokenizer.init(content);
        while (true) {
            std.debug.print("parse()\n", .{});
            if (try self.pop_section()) |el| {
                try root.push_child(el);
            } else if (try self.pop_paragraph()) |el| {
                try root.push_child(el);
            } else if (try self.pop_bullets()) |el| {
                try root.push_child(el);
            } else {
                break;
            }
        }

        return root;
    }

    fn pop_line(self: *Self) !?Node {
        var maybe_n: ?Node = null;
        while (self.next()) |token| {
            std.debug.print("Token {s}\n", .{token.word});
            if (maybe_n == null)
                maybe_n = Node.init(self.ma);
            if (maybe_n) |*n| {
                try n.line.append(token.word, Token.Kind.Text);
                if (is_newline(token))
                    break;
            } else unreachable;
        }
        return maybe_n;
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
};

// pub fn main() !void {
test "Parser.parse()" {
    var parser = Parser.init(ut.allocator);

    const content = "# Title1\n\n## Section\n\nLine\n- Bullet\n# Title2\nLine\n# Title3\n - Bullet\nLine\n# Title 4\n- b\n - bb\n- c";

    var root = try parser.parse(content);
    defer root.deinit();

    var n = naft.Node.init(null);
    root.write(&n);
}
