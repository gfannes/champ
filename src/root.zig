const std = @import("std");
const ut = std.testing;

pub const tkn = @import("amp/tkn.zig");
pub const config = @import("config.zig");

test {
    ut.refAllDecls(tkn);
    ut.refAllDecls(config);
}
