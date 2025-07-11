const std = @import("std");

const rubr = @import("rubr");

pub const Error = error{
    CannotExtendAbsolutePath,
    CannotShrink,
};

// Capital status spelling, similar to [todo-comments](https://github.com/folke/todo-comments.nvim)
pub const capitals = [_][]const u8{ "TODO", "NEXT", "WIP", "DONE", "QUESTION", "CALLOUT", "FORWARD", "CANCELED" };
// Lower-case variant. Infinite lifetime is important: amp.Path.Part blindly assumes its content lives long enough.
pub const lowers = [_][]const u8{ "todo", "next", "wip", "done", "question", "callout", "forward", "canceled" };

pub const Path = struct {
    const Self = @This();
    const Parts = std.ArrayList(Part);

    is_definition: bool = false,
    is_absolute: bool = false,
    is_dependency: bool = false,
    parts: Parts,

    pub fn init(a: std.mem.Allocator) Path {
        return Path{ .parts = Parts.init(a) };
    }
    pub fn deinit(self: *Self) void {
        self.parts.deinit();
    }
    pub fn copy(self: Path, a: std.mem.Allocator) !Path {
        var res = Path.init(a);
        res.is_definition = self.is_definition;
        res.is_absolute = self.is_absolute;
        res.is_dependency = self.is_dependency;
        for (self.parts.items) |part|
            // Assumes part is POD
            try res.parts.append(part);
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
                    if (!rubr.strings.contains(u8, &lowers, rhs_part.content))
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

    pub fn is_template(self: Self) bool {
        for (self.parts.items) |part|
            if (part.is_template)
                return true;
        return false;
    }

    // Assumes strange outlives Path
    pub fn parse(strange: *rubr.strng.Strange, a: std.mem.Allocator) !?Path {
        if (strange.popChar('&')) {
            var path = Path.init(a);
            errdefer path.deinit();

            path.is_definition = strange.popChar('&');
            path.is_absolute = strange.popChar(':');

            while (strange.popCharBack(':')) {}
            path.is_dependency = strange.popCharBack('&');

            while (strange.popTo(':')) |p|
                if (p.len > 0) {
                    var s = rubr.strng.Strange{ .content = p };
                    try path.parts.append(Part.init(&s));
                };

            if (strange.popAll()) |p|
                if (p.len > 0) {
                    var s = rubr.strng.Strange{ .content = p };
                    try path.parts.append(Part.init(&s));
                };

            return path;
        } else if (strange.popChar('[')) {
            var path = Path.init(a);
            errdefer path.deinit();

            if (strange.popOne()) |ch| {
                const content: []const u8 = switch (ch) {
                    ' ' => "todo",
                    '*' => "next",
                    '/' => "wip",
                    'x' => "done",
                    '?' => "question",
                    '!' => "callout",
                    '>' => "forward",
                    '-' => "canceled",
                    else => "unknown",
                };
                var s = rubr.strng.Strange{ .content = content };
                try path.parts.append(Part.init(&s));

                if (strange.popChar(']'))
                    return path;
            }

            path.deinit();
        } else if (rubr.strings.index(u8, &capitals, strange.str())) |ix| {
            var path = Path.init(a);
            errdefer path.deinit();

            var s = rubr.strng.Strange{ .content = lowers[ix] };
            try path.parts.append(Part.init(&s));

            return path;
        }

        return null;
    }

    pub fn prepend(self: *Self, prefix: Self) !void {
        self.is_definition = prefix.is_definition;
        self.is_absolute = prefix.is_absolute;
        // We do not copy is_dependency
        // Assumes Part is POD
        try self.parts.insertSlice(0, prefix.parts.items);
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
            try self.parts.insertSlice(0, rhs.parts.items[0..count_to_add]);
        }
    }

    pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("&", .{});
        if (self.is_definition)
            try writer.print("&", .{});
        var prefix: []const u8 = if (self.is_absolute) ":" else "";
        for (self.parts.items) |part| {
            const exclusive_str = if (part.is_exclusive) "!" else "";
            const template_str = if (part.is_template) "~" else "";
            try writer.print("{s}{s}{s}{s}", .{ prefix, exclusive_str, template_str, part.content });
            prefix = ":";
        }
        if (self.is_dependency)
            try writer.print("!", .{});
    }
};

// Part is assumed to be POD
pub const Part = struct {
    // content is assumed to output self
    content: []const u8,
    is_exclusive: bool = false,
    is_template: bool = false,

    pub fn init(strange: *rubr.strng.Strange) Part {
        const is_exclusive = strange.popChar('!');
        const is_template = strange.popChar('~');
        return Part{
            .content = strange.str(),
            .is_exclusive = is_exclusive,
            .is_template = is_template,
        };
    }
};

test "amp" {
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
        .{ .repr = "&&:a:b!:c", .exp = "&&:a:b!:c" },
        .{ .repr = "&&:a:b!:c:", .exp = "&&:a:b!:c" },
        .{ .repr = "&&:status:~status", .exp = "&&:status:~status" },
        .{ .repr = "&abc!", .exp = "&abc!" },
    };

    for (scns) |scn| {
        var strange = rubr.strng.Strange{ .content = scn.repr };
        var path = try Path.parse(&strange, ut.allocator) orelse unreachable;
        defer path.deinit();
        const act = try std.fmt.allocPrint(ut.allocator, "{s}", .{path});
        try ut.expectEqualSlices(u8, scn.exp, act);
        defer ut.allocator.free(act);
    }
}
