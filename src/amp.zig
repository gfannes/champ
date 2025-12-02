pub const Path = @import("amp/Path.zig");
pub const Status = @import("amp/Status.zig");
pub const Prio = @import("amp/Prio.zig");
pub const Date = @import("amp/Date.zig");
pub const Def = @import("amp/Def.zig");
pub const DefMgr = @import("amp/DefMgr.zig");

test {
    const ut = @import("std").testing;

    ut.refAllDecls(Path);
    ut.refAllDecls(Status);
    ut.refAllDecls(Prio);
    ut.refAllDecls(Date);
    ut.refAllDecls(Def);
    ut.refAllDecls(DefMgr);
}
