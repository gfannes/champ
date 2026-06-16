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
    InvalidCost,
    InvalidPrio,
    InvalidWorker,
    InvalidWbs,
};

const Self = @This();

pub const Cost = struct {
    value: u32,
};
pub const Order = struct {
    value: i32,
    relative: bool,
};
pub const Worker = struct {
    name: []const u8,
};

pub const Unnamed = struct {
    id: usize,
};

// Part is assumed to be POD
pub const Part = struct {
    pub const Meta = union(enum) {
        cost: Cost,
        order: Order,
        worker: Worker,
        wbs: Wbs,
        status: Status,
        date: Date,

        unnamed: Unnamed,
    };

    is_exclusive: bool = false,
    content: []const u8,
    meta: ?Meta = null,

    status: ?Status = null,
    date: ?Date = null,
    order: ?Order = null,
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

pub fn isMeta(self: Self) bool {
    if (self.parts.items.len == 0)
        return false;
    return self.parts.items[0].meta != null;
}
pub fn isStatus(self: Self) bool {
    if (self.parts.items.len == 0)
        return false;
    return std.meta.activeTag(self.parts.items[0].meta orelse return false) == .status;
}
pub fn isOrder(self: Self) bool {
    if (self.parts.items.len == 0)
        return false;
    return std.meta.activeTag(self.parts.items[0].meta orelse return false) == .order;
}

// rhs is the smaller one
pub fn isFit(self: Self, rhs: Self) bool {
    var rhs_rit = std.mem.reverseIterator(rhs.parts.items);
    var self_rit = std.mem.reverseIterator(self.parts.items);
    while (rhs_rit.nextPtr()) |rhs_part| {
        const self_part: *const Part = self_rit.nextPtr() orelse return false;
        if (!std.mem.eql(u8, rhs_part.content, self_part.content))
            return false;
    }

    if (rhs.is_absolute and self_rit.nextPtr() != null)
        return false;

    return true;
}

// Assumes strange outlives Self
pub fn parse(strange: *rubr.strng.Strange, a: std.mem.Allocator) !Self {
    var path = Self.init(a);
    errdefer path.deinit();

    if (strange.popChar('&')) {
        var is_exclusive = strange.popChar('^');

        if (strange.popChar('$')) {
            try path.parts.append(a, Part{ .content = "_cost", .meta = Part.Meta{ .cost = Cost{ .value = strange.popInt(u32) orelse return error.InvalidCost } } });

            return path;
        } else if (strange.popChar('#')) {
            const relative = if (strange.front()) |ch| ch == '+' or ch == '-' else false;
            try path.parts.append(a, Part{ .content = "_order", .meta = Part.Meta{ .order = Order{ .value = strange.popInt(i32) orelse return error.InvalidOrder, .relative = relative } } });

            return path;
        } else if (strange.popChar('@')) {
            try path.parts.append(a, Part{ .content = "_worker", .is_exclusive = is_exclusive, .meta = Part.Meta{ .worker = Worker{ .name = strange.popAll() orelse return error.InvalidWorker } } });

            return path;
        } else if (strange.popChar('?')) {
            try path.parts.append(a, Part{ .content = "_wbs", .meta = Part.Meta{ .wbs = Wbs.parse(strange.str(), .{}) orelse return error.InvalidWbs } });

            return path;
        } else if (Date.parse(strange.str(), .{})) |date| {
            try path.parts.append(a, Part{ .content = "_date", .meta = Part.Meta{ .date = date } });

            return path;
        } else if (Status.fromLower(strange.str())) |status| {
            try path.parts.append(a, Part{ .content = "_status", .meta = Part.Meta{ .status = status } });

            return path;
        } else {
            path.is_definition = strange.popChar('&');
            path.is_absolute = strange.popChar(':');

            while (strange.popCharBack(':')) {}
            path.is_dependency = strange.popCharBack('&');

            while (!strange.empty()) {
                var maybe_content = strange.popTo(':');
                if (maybe_content == null)
                    maybe_content = strange.popAll();

                if (maybe_content) |content| {
                    try path.parts.append(a, Part{ .content = content, .is_exclusive = is_exclusive });

                    is_exclusive = strange.popChar('^');
                }
            }

            return path;
        }
    } else if (strange.popStr("[[") and strange.popStrBack("]]")) {
        try path.parts.append(a, Part{ .content = strange.str() });

        return path;
    } else if (strange.popChar('[')) {
        if (strange.popOne()) |ch| {
            const content: []const u8 = switch (ch) {
                ' ' => "todo",
                '*' => "go",
                '/' => "wip",
                'x' => "done",
                '?' => "question",
                'i' => "info",
                '!' => "blocked",
                '>' => "forward",
                '<' => "planned",
                '-' => "canceled",
                '~' => "assigned",
                else => "unknown",
            };
            if (strange.popChar(']')) {
                if (Status.fromLower(content)) |status| {
                    try path.parts.append(a, Part{ .content = "_status", .meta = Part.Meta{ .status = status } });

                    return path;
                }
            }
        }
    } else if (Status.fromCapital(strange.str())) |status| {
        try path.parts.append(a, Part{ .content = "_status", .meta = Part.Meta{ .status = status } });

        return path;
    }

    return error.ExpectedAmp;
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
        const exclusive_str = if (part.is_exclusive) "^" else "";
        try io.print("{s}{s}{s}", .{ prefix, exclusive_str, part.content });
        if (part.meta) |meta| {
            switch (meta) {
                .cost => |cost| try io.print(":{}", .{cost.value}),
                .order => |order| try io.print(":{}", .{order.value}),
                .worker => |worker| try io.print(":{s}", .{worker.name}),
                .wbs => |wbs| try io.print(":{s}", .{wbs.lower()}),
                .status => |status| try io.print(":{s}", .{status.lower()}),
                .date => |date| try io.print(":{}", .{date.date.epoch_day.day}),
                .unnamed => |unnamed| try io.print(":{}", .{unnamed.id}),
            }
        }
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

        .{ .repr = "&$123", .exp = "&_cost:123" },
        .{ .repr = "&#123", .exp = "&_order:123" },
        .{ .repr = "&#-123", .exp = "&_order:-123" },
        .{ .repr = "&@geert", .exp = "&_worker:geert" },
        .{ .repr = "&^@geert", .exp = "&^_worker:geert" },
        .{ .repr = "&?proj", .exp = "&_wbs:project" },
        .{ .repr = "&todo", .exp = "&_status:todo" },
        .{ .repr = "&go", .exp = "&_status:go" },
        .{ .repr = "&wip", .exp = "&_status:wip" },
        .{ .repr = "&done", .exp = "&_status:done" },
        .{ .repr = "TODO", .exp = "&_status:todo" },
        .{ .repr = "GO", .exp = "&_status:go" },
        .{ .repr = "WIP", .exp = "&_status:wip" },
        .{ .repr = "DONE", .exp = "&_status:done" },
        .{ .repr = "[ ]", .exp = "&_status:todo" },
        .{ .repr = "[*]", .exp = "&_status:go" },
        .{ .repr = "[/]", .exp = "&_status:wip" },
        .{ .repr = "[x]", .exp = "&_status:done" },
        .{ .repr = "[~]", .exp = "&_status:assigned" },
        .{ .repr = "&2027", .exp = "&_date:20819" },
    };

    for (scns) |scn| {
        std.debug.print("{s}\n", .{scn.repr});
        var strange = rubr.strng.Strange{ .content = scn.repr };
        var path = try Self.parse(&strange, ut.allocator);
        defer path.deinit();
        const act = try std.fmt.allocPrint(ut.allocator, "{f}", .{path});
        try ut.expectEqualSlices(u8, scn.exp, act);
        defer ut.allocator.free(act);
    }
}
