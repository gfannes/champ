pub const Path = @import("amp/Path.zig");
pub const Status = @import("amp/Status.zig");
pub const Prio = @import("amp/Prio.zig");

test {
    const ut = @import("std").testing;

    ut.refAllDecls(Path);
    ut.refAllDecls(Status);
    ut.refAllDecls(Prio);
}
