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
        n.attr("word", self.word);
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
        for (self.tokens.items) |token|
            token.write(&n);
    }
};

pub const Node = struct {
    const Self = @This();
    const Childs = std.ArrayList(Node);

    line: Line,
    childs: Childs,
    ma: std.mem.Allocator,

    pub fn init(ma: std.mem.Allocator) !Self {
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
            try self.childs.append(try Node.init(self.ma));
        }
        return &self.childs.items[ix];
    }

    pub fn write(self: Self, parent: *naft.Node) void {
        var n = parent.node("Node");
        defer n.deinit();
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

    pub fn init(ma: std.mem.Allocator) Self {
        return Self{ .ma = ma };
    }

    pub fn parse(self: *Self, content: []const u8) !Node {
        var tokenizer = tkn.Tokenizer.init(content);

        var root = try Node.init(self.ma);
        var child_ix: usize = 0;

        while (tokenizer.next()) |token| {
            std.debug.print("Token: {s}\n", .{token.word});

            if (token.symbol == tkn.Symbol.Newline) {
                child_ix += token.word.len;
            } else {
                var child = try root.goc_child(child_ix);
                try child.line.append(token.word, Kind.Text);
            }
        }

        return root;
    }
};

test "Parser.parse()" {
    var parser = Parser.init(ut.allocator);

    const content = "# Title\n\n## Section\n\nLine\n- Bullet";

    var root = try parser.parse(content);
    defer root.deinit();

    var n = naft.Node.init(null);
    root.write(&n);
}
