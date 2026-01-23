const std = @import("std");

pub const Path = @import("amp/Path.zig");
pub const Status = @import("amp/Status.zig");
pub const Prio = @import("amp/Prio.zig");
pub const Date = @import("amp/Date.zig");
pub const Def = @import("amp/Def.zig");
pub const DefMgr = @import("amp/DefMgr.zig");

pub fn is_folder_metadata_fp(path: []const u8) bool {
    return std.mem.endsWith(u8, path, "&.md");
}

test {
    const ut = @import("std").testing;

    ut.refAllDecls(Path);
    ut.refAllDecls(Status);
    ut.refAllDecls(Prio);
    ut.refAllDecls(Date);
    ut.refAllDecls(Def);
    ut.refAllDecls(DefMgr);
}
