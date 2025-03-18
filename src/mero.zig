const std = @import("std");
const ut = std.testing;

const tkn = @import("tkn.zig");

pub const Parser = struct {
    const Self = @This();
    const Strings = std.ArrayList([]const u8);

    lines: Strings,

    pub fn init(ma: std.mem.Allocator) Self {
        return Self{ .lines = Strings.init(ma) };
    }
    pub fn deinit(self: *Self) void {
        self.lines.deinit();
    }

    pub fn parse(self: *Self, content: []const u8) !void {
        var tokenizer = tkn.Tokenizer.init(content);
        var line: []const u8 = &.{};
        while (tokenizer.next()) |token| {
            std.debug.print("Token: {s}\n", .{token.word});

            if (token.symbol == tkn.Symbol.Newline) {
                try self.lines.append(line);
                for (0..token.word.len - 1) |_|
                    try self.lines.append(&.{});
                line.len = 0;
            } else if (line.len == 0) {
                line = token.word;
            } else {
                line.len += token.word.len;
            }
        }
    }
};
