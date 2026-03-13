const rubr = @import("rubr.zig");

pub const Pos = struct {
    row: usize = 0,
    cols: rubr.idx.Range = .{},
};
