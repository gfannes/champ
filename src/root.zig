const std = @import("std");
const ut = std.testing;

pub const app = @import("app.zig");
pub const tkn = @import("tkn.zig");
pub const config = @import("config.zig");
pub const mero = @import("mero.zig");

test {
    ut.refAllDecls(app);
    ut.refAllDecls(tkn);
    ut.refAllDecls(config);
    ut.refAllDecls(mero);
}
