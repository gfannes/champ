const std = @import("std");

const tkn = @import("tkn.zig");

pub const Error = error{
    ExpectedExclamation,
};

pub const Link = struct {
    const Self = @This();
    content: []const u8,

    pub fn image_filepath(self: Self) ?[]const u8 {
        const Cb = struct {
            first: bool = true,
            collect: bool = false,
            res: ?[]const u8 = null,
            pub fn call(my: *@This(), token: tkn.Token) !void {
                if (my.first) {
                    my.first = false;
                    if (token.symbol != .Exclamation)
                        return error.ExpectedExclamation;
                }
                switch (token.symbol) {
                    .OpenParens => my.collect = true,
                    .CloseParens => my.collect = false,
                    else => if (my.collect) {
                        if (my.res) |*res|
                            res.len += token.word.len
                        else
                            my.res = token.word;
                    },
                }
            }
        };
        var cb = Cb{};

        var tokenizer = tkn.Tokenizer{ .content = self.content };
        tokenizer.each(&cb) catch return null;

        return cb.res;
    }
};
