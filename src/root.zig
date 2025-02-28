const std = @import("std");
const ut = std.testing;

pub const tkn = @import("amp/tkn.zig");

test {
    ut.refAllDecls(tkn);
}
