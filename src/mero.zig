const std = @import("std");
const ut = std.testing;

const naft = @import("rubr").naft;

const tkn = @import("tkn.zig");

pub const Kind = enum {
    Text,
    Amp,
};

pub const Token = struct {
    const Self = @This();

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

    pub fn append(self: *Self, word: []const u8, kind: Kind) !void {
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
            if (try self.section()) |el| {
                try root.childs.append(el);
            } else if (try self.paragraph()) |el| {
                try root.childs.append(el);
            } else if (try self.bullets()) |el| {
                try root.childs.append(el);
            } else {
                break;
            }
        }

        return root;
    }

    fn line(self: *Self) !?Node {
        var maybe_n: ?Node = null;
        while (self.next()) |token| {
            std.debug.print("Token {s}\n", .{token.word});
            if (maybe_n == null)
                maybe_n = Node.init(self.ma);
            if (maybe_n) |*n| {
                try n.line.append(token.word, Kind.Text);
                if (token.symbol == tkn.Symbol.Newline)
                    break;
            } else unreachable;
        }
        return maybe_n;
    }

    fn section(self: *Self) !?Node {
        if (self.peek()) |first_token| {
            if (first_token.symbol == tkn.Symbol.Hashtag) {
                var n = try self.line() orelse unreachable;
                n.type = Node.Type.Section;

                while (self.peek()) |token| {
                    if (token.symbol == tkn.Symbol.Hashtag) {
                        if (token.word.len <= first_token.word.len)
                            // This is the start of a section we cannot nest
                            break;
                        try n.childs.append(try self.section() orelse unreachable);
                    } else if (try self.paragraph()) |p| {
                        try n.childs.append(p);
                    } else if (try self.bullets()) |p| {
                        try n.childs.append(p);
                    } else break;
                }

                return n;
            }
        }
        return null;
    }

    fn paragraph(self: *Self) !?Node {
        if (self.peek()) |first_token| {
            if (first_token.symbol != tkn.Symbol.Hashtag and first_token.symbol != tkn.Symbol.Space and first_token.symbol != tkn.Symbol.Minus and first_token.symbol != tkn.Symbol.Star) {
                var n = try self.line() orelse unreachable;
                n.type = Node.Type.Paragraph;

                while (try self.bullets()) |p| {
                    try n.childs.append(p);
                }
                return n;
            }
        }
        return null;
    }

    fn bullets(self: *Self) !?Node {
        if (self.peek()) |first_token| {
            if (first_token.symbol != tkn.Symbol.Hashtag) {
                var n = try self.line() orelse unreachable;
                n.type = Node.Type.Bullets;

                while (try self.bullets()) |p| {
                    try n.childs.append(p);
                }
                return n;
            }
        }
        return null;
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

    const content = "# Title1\n\n## Section\n\nLine\n- Bullet\n# Title2\nLine\n# Title3\n - Bullet";

    var root = try parser.parse(content);
    defer root.deinit();

    var n = naft.Node.init(null);
    root.write(&n);
}
