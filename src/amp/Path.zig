const std = @import("std");

const rubr = @import("rubr");
const Status = @import("Status.zig");
const Prio = @import("Prio.zig");
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
    UnsupportedTemplate,
};

const Self = @This();

// Part is assumed to be POD
pub const Part = struct {
    content: []const u8,
    status: ?Status = null,
    date: ?Date = null,
    prio: ?Prio = null,
    wbs: ?Wbs = null,
    is_exclusive: bool = false,
    is_template: bool = false,

    pub fn init(strange: *rubr.strng.Strange) Part {
        const is_exclusive = strange.popChar('!');
        const is_template_ = strange.popChar('~');
        return Part{
            .content = strange.str(),
            .is_exclusive = is_exclusive,
            .is_template = is_template_,
        };
    }
};
const Parts = std.ArrayList(Part);

a: std.mem.Allocator,
is_definition: bool = false,
is_absolute: bool = false,
is_dependency: bool = false,
parts: Parts = .{},

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
    var rhs_rit = std.mem.reverseIterator(rhs.parts.items);
    var self_rit = std.mem.reverseIterator(self.parts.items);
    while (rhs_rit.nextPtr()) |rhs_part| {
        const self_part: *const Part = self_rit.nextPtr() orelse return false;
        if (self_part.is_template) {
            if (std.mem.eql(u8, self_part.content, "status")) {
                if (Status.fromLower(rhs_part.content) == null)
                    return false;
            } else if (std.mem.eql(u8, self_part.content, "date")) {
                if (Date.parse(rhs_part.content, .{}) == null)
                    return false;
            } else if (std.mem.eql(u8, self_part.content, "prio")) {
                if (Prio.parse(rhs_part.content, .{}) == null)
                    return false;
            } else if (std.mem.eql(u8, self_part.content, "wbs")) {
                if (Wbs.parse(rhs_part.content, .{}) == null)
                    return false;
            } else {
                // std.debug.print("Unsupported template '{s}'\n", .{self_part.content});
                return false;
            }
        } else {
            if (!std.mem.eql(u8, rhs_part.content, self_part.content))
                return false;
        }
    }

    if (rhs.is_absolute and self_rit.nextPtr() != null)
        return false;

    return true;
}

pub fn value_at(self: Self, key: []const []const u8) ?*const Part {
    if (self.parts.items.len != key.len + 1)
        return null;

    for (self.parts.items[0..key.len], key) |part, k| {
        if (!std.mem.eql(u8, part.content, k))
            return null;
    }

    return &self.parts.items[key.len];
}

pub fn evaluate(self: Self, ap: *Self) !void {
    if (self.parts.items.len != ap.parts.items.len)
        return Error.ExpectedSameLen;

    for (self.parts.items, ap.parts.items) |src, *dst| {
        if (!src.is_template)
            continue;
        if (std.mem.eql(u8, src.content, "status")) {
            dst.status = Status.fromLower(dst.content) orelse return Error.ExpectedStatus;
        } else if (std.mem.eql(u8, src.content, "date")) {
            dst.date = Date.parse(dst.content, .{}) orelse return Error.ExpectedDate;
        } else if (std.mem.eql(u8, src.content, "prio")) {
            dst.prio = Prio.parse(dst.content, .{}) orelse return Error.ExpectedPrio;
        } else if (std.mem.eql(u8, src.content, "wbs")) {
            dst.wbs = Wbs.parse(dst.content, .{}) orelse return Error.ExpectedWbs;
        } else {
            std.debug.print("Unsupported template '{s}'\n", .{src.content});
            return Error.UnsupportedTemplate;
        }
    }
}

pub fn is_template(self: Self) bool {
    for (self.parts.items) |part|
        if (part.is_template)
            return true;
    return false;
}

// Assumes strange outlives Self
pub fn parse(strange: *rubr.strng.Strange, a: std.mem.Allocator) !?Self {
    if (strange.popChar('&')) {
        var path = Self.init(a);
        errdefer path.deinit();

        path.is_definition = strange.popChar('&');
        path.is_absolute = strange.popChar(':');

        while (strange.popCharBack(':')) {}
        path.is_dependency = strange.popCharBack('&');

        while (strange.popTo(':')) |p|
            if (p.len > 0) {
                var s = rubr.strng.Strange{ .content = p };
                try path.parts.append(a, Part.init(&s));
            };

        if (strange.popAll()) |p|
            if (p.len > 0) {
                var s = rubr.strng.Strange{ .content = p };
                try path.parts.append(a, Part.init(&s));
            };

        return path;
    } else if (strange.popChar('[')) {
        var path = Self.init(a);
        errdefer path.deinit();

        if (strange.popOne()) |ch| {
            const content: []const u8 = switch (ch) {
                ' ' => "todo",
                '*' => "next",
                '/' => "wip",
                'x' => "done",
                '?' => "question",
                'i' => "info",
                '!' => "blocked",
                '>' => "forward",
                '-' => "canceled",
                else => "unknown",
            };
            var s = rubr.strng.Strange{ .content = content };
            try path.parts.append(a, Part.init(&s));

            if (strange.popChar(']'))
                return path;
        }

        path.deinit();
    } else if (Status.fromCapital(strange.str())) |status| {
        var path = Self.init(a);
        errdefer path.deinit();

        var s = rubr.strng.Strange{ .content = status.lower() };
        try path.parts.append(a, Part.init(&s));

        return path;
    }

    return null;
}

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

pub fn format(self: Self, io: *std.Io.Writer) !void {
    try io.print("&", .{});
    if (self.is_definition)
        try io.print("&", .{});
    var prefix: []const u8 = if (self.is_absolute) ":" else "";
    for (self.parts.items) |part| {
        const exclusive_str = if (part.is_exclusive) "!" else "";
        const template_str = if (part.is_template) "~" else "";
        try io.print("{s}{s}{s}{s}", .{ prefix, exclusive_str, template_str, part.content });
        prefix = ":";
    }
    if (self.is_dependency)
        try io.print("&", .{});
}

test "amp.Path" {
    const ut = std.testing;

    const Scn = struct {
        repr: []const u8,
        exp: []const u8,
    };

    const scns = [_]Scn{
        .{ .repr = "&abc", .exp = "&abc" },
        .{ .repr = "&&abc", .exp = "&&abc" },
        .{ .repr = "&:abc", .exp = "&:abc" },
        .{ .repr = "&&:abc", .exp = "&&:abc" },
        .{ .repr = "&&:!abc", .exp = "&&:!abc" },
        .{ .repr = "&&:!abc:", .exp = "&&:!abc" },
        .{ .repr = "&&:a:b&:c", .exp = "&&:a:b&:c" },
        .{ .repr = "&&:a:b&:c:", .exp = "&&:a:b&:c" },
        .{ .repr = "&&:status:~status", .exp = "&&:status:~status" },
        .{ .repr = "&abc&", .exp = "&abc&" },
    };

    for (scns) |scn| {
        var strange = rubr.strng.Strange{ .content = scn.repr };
        var path = try Self.parse(&strange, ut.allocator) orelse unreachable;
        defer path.deinit();
        const act = try std.fmt.allocPrint(ut.allocator, "{f}", .{path});
        try ut.expectEqualSlices(u8, scn.exp, act);
        defer ut.allocator.free(act);
    }
}
