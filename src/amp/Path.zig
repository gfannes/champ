const std = @import("std");

const rubr = @import("../rubr.zig");
const Status = @import("Status.zig");
const Date = @import("Date.zig");
const Wbs = @import("Wbs.zig");

pub const Error = error{
    CannotExtendAbsolutePath,
    CannotShrink,
    ExpectedSameLen,
    ExpectedStatus,
    ExpectedDate,
    ExpectedPrio,
    ExpectedWbs,
    ExpectedAmp,
};

const Self = @This();

// Part is assumed to be POD
pub const Part = struct {
    is_exclusive: bool = false,
    content: []const u8,
};
const Parts = std.ArrayList(Part);

a: std.mem.Allocator,

is_definition: bool = false, // &&name
is_absolute: bool = false, // &&:name
is_dependency: bool = false, // &name&
parts: Parts = .empty,

pub fn init(a: std.mem.Allocator) Self {
    return Self{ .a = a };
}
pub fn deinit(self: *Self) void {
    self.parts.deinit(self.a);
}
pub fn copy(self: Self, a: std.mem.Allocator) !Self {
    var res = Self.init(a);
    res.is_definition = self.is_definition;
    res.is_absolute = self.is_absolute;
    res.is_dependency = self.is_dependency;
    for (self.parts.items) |part|
        // Assumes part is POD
        try res.parts.append(res.a, part);
    return res;
}

// rhs is the smaller one
pub fn isFit(self: Self, rhs: Self) bool {
    const self_len = self.parts.items.len;
    const rhs_len = rhs.parts.items.len;

    if (rhs_len > self_len)
        // rhs is longer: this cannot fit
        return false;
    const self_offset = self_len - rhs_len;

    if (rhs.is_absolute and self_offset != 0)
        // if rhs is absolute, it can only match with self if the length is the same
        return false;

    for (self.parts.items[self_offset..], rhs.parts.items) |self_part, rhs_part| {
        if (!std.mem.eql(u8, self_part.content, rhs_part.content))
            // this part is different
            return false;
    }

    return true;
}

// Assumes strange outlives Self

pub fn prepend(self: *Self, prefix: Self) !void {
    self.is_definition = prefix.is_definition;
    self.is_absolute = prefix.is_absolute;
    // We do not copy is_dependency
    // Assumes Part is POD
    try self.parts.insertSlice(self.a, 0, prefix.parts.items);
}

pub fn prependString(self: *Self, str: []const u8) !void {
    const part = Part{ .content = str };
    try self.parts.insert(self.a, 0, part);
}

pub fn extend(self: *Self, rhs: Self) !void {
    if (self.is_absolute) {
        if (self.parts.items.len != rhs.parts.items.len)
            return Error.CannotExtendAbsolutePath;
    } else {
        if (rhs.parts.items.len < self.parts.items.len)
            return Error.CannotShrink;
        self.is_definition = rhs.is_definition;
        self.is_absolute = rhs.is_absolute;
        // We do not copy is_dependency
        const count_to_add = rhs.parts.items.len - self.parts.items.len;
        try self.parts.insertSlice(self.a, 0, rhs.parts.items[0..count_to_add]);
    }
}

pub fn format(self: Self, w: *std.Io.Writer) !void {
    try w.print("&", .{});
    if (self.is_definition)
        try w.print("&", .{});
    var prefix: []const u8 = if (self.is_absolute) ":" else "";
    for (self.parts.items) |part| {
        const exclusive_str = if (part.is_exclusive) "^" else "";
        try w.print("{s}{s}{s}", .{ prefix, exclusive_str, part.content });
        prefix = ":";
    }
    if (self.is_dependency)
        try w.print("&", .{});
}
