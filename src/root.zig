const std = @import("std");

pub const app = @import("app.zig");
pub const tkn = @import("tkn.zig");
pub const cfg = @import("cfg.zig");
pub const mero = @import("mero.zig");
pub const chorex = @import("chorex.zig");
pub const amp = @import("amp.zig");
pub const filex = @import("filex.zig");

test {
    const ut = std.testing;
    ut.refAllDecls(app);
    ut.refAllDecls(tkn);
    ut.refAllDecls(cfg);
    ut.refAllDecls(mero);
    ut.refAllDecls(chorex);
    ut.refAllDecls(amp);
    ut.refAllDecls(filex);
}
