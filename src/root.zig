const std = @import("std");
const ut = std.testing;

pub const app = @import("app.zig");
pub const tkn = @import("tkn.zig");
pub const cfg = @import("cfg.zig");
pub const mero = @import("mero.zig");
pub const chore = @import("chore.zig");
pub const amp = @import("amp.zig");

test {
    ut.refAllDecls(app);
    ut.refAllDecls(tkn);
    ut.refAllDecls(cfg);
    ut.refAllDecls(mero);
    ut.refAllDecls(chore);
    ut.refAllDecls(amp);
}
