const std = @import("std");
const ut = std.testing;

const tkn = @import("tkn.zig");

pub const Parser = struct {
    const Self = @This();
    const Strings = std.ArrayList([]const u8);

    tokens: *const tkn.Tokenizer,

    lines: Strings,

    pub fn init(tokens: *const tkn.Tokenizer, ma: std.mem.Allocator) Parser {
        return Parser{ .tokens = tokens, .lines = Strings.init(ma) };
    }
    pub fn deinit(self: *Self) void {
        self.lines.deinit();
    }

    pub fn parse(_: *Parser) !void {
        std.debug.print("Parser.parse\n", .{});
        // for (self.tokens._tokens.items) |token| {
        //     try self.lines.append(token.word);
        // }
        // for (self.lines.items) |line| {
        //     std.debug.print("Line: ({s})\n", .{line});
        // }
        std.debug.print("Parser.parse\n", .{});
    }
};
