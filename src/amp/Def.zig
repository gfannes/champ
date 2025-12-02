const rubr = @import("rubr");
const Path = @import("Path.zig");
const filex = @import("../filex.zig");

const Self = @This();

pub const Ix = rubr.idx.Ix(@This());

pub const Location = struct {
    grove_id: usize,
    path: []const u8,
    node_id: usize,
    pos: filex.Pos,
};

ap: Path,
location: ?Location = null,
template: ?Ix = null,

pub fn deinit(self: *Self) void {
    self.ap.deinit();
}

pub fn write(self: Self, parent: *rubr.naft.Node) void {
    var n = parent.node("Def");
    defer n.deinit();
    n.attr("ap", self.ap);
    if (self.location) |loc| {
        n.attr("grove_id", loc.grove_id);
        n.attr("path", loc.path);
        n.attr("row", loc.pos.row);
        n.attr("cols.begin", loc.pos.cols.begin);
        n.attr("cols.end", loc.pos.cols.end);
    }
}
