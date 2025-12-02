const rubr = @import("rubr");

pub const Pos = struct {
    row: usize = 0,
    cols: rubr.idx.Range = .{},
};
