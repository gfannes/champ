const std = @import("std");

const Meta = @import("Meta.zig");

const filex = @import("../filex.zig");
const rubr = @import("../rubr.zig");

const Self = @This();

pub const Location = struct {
    path: []const u8 = &.{},
    pos: ?filex.Pos = null,
    dto_id: ?usize = null,

    pub fn write(self: @This(), parent: *rubr.naft.Node) void {
        var n = parent.node("Location");
        defer n.deinit();
        n.attr("path", self.path);
        if (self.pos) |pos|
            n.attr("row", pos.row);
        if (self.dto_id) |dto_id|
            n.attr("dto_id", dto_id);
    }
};

a: std.mem.Allocator,
name: ?[]const u8 = null,
locations: std.ArrayList(Location) = .empty,
ancestors: std.ArrayList(usize) = .empty,
direct_ancestor_count: usize = 0,
meta: ?Meta = null,

pub fn init(self: *Self, a: std.mem.Allocator, name: ?[]const u8) void {
    self.* = .{
        .a = a,
        .name = name,
    };
}

pub fn deinit(self: *Self) void {
    self.locations.deinit(self.a);
    self.ancestors.deinit(self.a);
    if (self.meta) |*meta|
        meta.deinit();
}

pub fn appendLocation(self: *Self, filepath: []const u8, pos: filex.Pos, dto_id: usize) !void {
    try self.locations.append(self.a, .{ .path = filepath, .pos = pos, .dto_id = dto_id });
}

pub fn updateMeta(self: *Self, meta: Meta) !void {
    if (!meta.hasData())
        return;
    if (self.meta) |*m| {
        try m.update(meta);
    } else {
        self.meta = try meta.dup(self.a);
    }
}

pub fn write(self: Self, parent: *rubr.naft.Node) void {
    var n = parent.node("Node");
    defer n.deinit();

    if (self.name) |name|
        n.attr("name", name);

    self.meta.write(&n);
    for (self.locations.items) |location| {
        location.write(&n);
    }
}

pub fn format(self: Self, w: *std.Io.Writer) !void {
    rubr.naft.Node.write(self, w);
}
