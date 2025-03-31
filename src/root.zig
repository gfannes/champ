const std = @import("std");
const ut = std.testing;

pub const app = @import("app.zig");
pub const tkn = @import("tkn.zig");
pub const cfg = @import("cfg.zig");
pub const cfg_ = @import("cfg_.zig");
pub const mero = @import("mero.zig");
pub const lsp = @import("lsp.zig");

test {
    ut.refAllDecls(app);
    ut.refAllDecls(tkn);
    ut.refAllDecls(cfg);
    ut.refAllDecls(cfg_);
    ut.refAllDecls(mero);
    ut.refAllDecls(lsp);
}
