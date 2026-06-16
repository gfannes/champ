const std = @import("std");

const rubr = @import("rubr.zig");

const Chore = @import("chorex.zig").Chore;
const amp = @import("amp.zig");

pub const Query = struct {
    const Self = @This();
    const Parts = std.ArrayList([]const u8);
    pub const Include = struct {
        const My = @This();
        done: bool = false,
        todo: bool = false,
        go: bool = false,
        wip: bool = false,
        canceled: bool = false,
        question: bool = false,
        info: bool = false,
        blocked: bool = false,
        forward: bool = false,

        pub fn set_all(my: *My, val: bool) void {
            inline for (@typeInfo(My).@"struct".fields) |field|
                @field(my, field.name) = val;
        }
        pub fn is_all(my: My, val: bool) bool {
            inline for (@typeInfo(My).@"struct".fields) |field| {
                const my_val = @field(my, field.name);
                if (my_val != val)
                    return false;
            }
            return true;
        }
    };

    a: std.mem.Allocator,
    include: Include = .{},
    only_status: bool = false,
    only_def: bool = false,
    only_org: bool = false,
    parts: Parts = .empty,
    aps: std.ArrayList(*const amp.Path) = .empty,

    pub fn deinit(self: *Self) void {
        for (self.parts.items) |part|
            self.a.free(part);
        self.parts.deinit(self.a);
        self.aps.deinit(self.a);
    }

    pub fn setup(self: *Self, parts: []const []const u8) !void {
        for (parts) |part| {
            var strange = rubr.strng.Strange{ .content = part };

            while (!strange.empty()) {
                if (strange.popChar('.')) {
                    self.include.set_all(true);
                    self.only_status = true;
                } else if (strange.popChar(' ') or strange.popChar(',')) {
                    self.include.todo = true;
                    self.only_status = true;
                } else if (strange.popChar('x')) {
                    self.include.done = true;
                    self.only_status = true;
                } else if (strange.popChar('/')) {
                    self.include.wip = true;
                    self.only_status = true;
                } else if (strange.popChar('*')) {
                    self.include.go = true;
                    self.only_status = true;
                } else if (strange.popChar('-')) {
                    self.include.canceled = true;
                    self.only_status = true;
                } else if (strange.popChar('i')) {
                    self.include.info = true;
                    self.only_status = true;
                } else if (strange.popChar('!')) {
                    self.include.blocked = true;
                    self.only_status = true;
                } else if (strange.popChar('?')) {
                    self.include.question = true;
                    self.only_status = true;
                } else if (strange.popChar('>')) {
                    self.include.forward = true;
                    self.only_status = true;
                }

                const str: []const u8 = if (strange.popTo(' ')) |str| str else if (strange.popAll()) |str| str else &.{};
                if (str.len > 0)
                    try self.parts.append(self.a, try self.a.dupe(u8, str));
            }
        }

        if (self.include.is_all(false)) {
            self.include.set_all(true);
            self.include.done = false;
        }
    }

    pub fn prepare(self: *Self, chore: Chore) !void {
        try self.aps.resize(self.a, 0);
        _ = chore;
    }

    pub fn add(self: *Self, ap: *const amp.Path) !void {
        try self.aps.append(self.a, ap);
    }

    pub fn distance(self: Self) ?f64 {
        var sum_distance: f64 = 0;
        for (self.parts.items) |q_part| {
            // std.debug.print("Matching '{s}'\n", .{q_part});
            var maybe_min_distance: ?f64 = null;
            for (self.aps.items) |ap| {
                for (ap.parts.items) |a_part| {
                    var skip_count: usize = undefined;
                    const dist = rubr.fuzz.distance(q_part, a_part.content, &skip_count);
                    // std.debug.print("\t'{s}' '{s}' {} {}\n", .{ q_part, a_part.content, score, skip_count });
                    if (skip_count > 0)
                        continue;
                    maybe_min_distance = @min(dist, maybe_min_distance orelse dist);
                }
            }

            sum_distance += maybe_min_distance orelse return null;
        }

        return sum_distance;
    }

    pub fn distance_(self: Self, chore: Chore, aps: []*const amp.Path) ?f64 {
        var has_def: bool = false;
        var status_is_match: ?bool = null;

        const chore_parts = if (self.only_org) chore.parts.items[0..chore.org_count] else chore.parts.items;

        for (chore_parts) |part| {
            if (part.ap.is_definition)
                has_def = true;

            const last = rubr.slc.lastPtrUnsafe(part.ap.parts.items).content;
            if (std.mem.eql(u8, last, "done") and self.include.done)
                status_is_match = true;
            if (std.mem.eql(u8, last, "todo") and self.include.todo)
                status_is_match = true;
            if (std.mem.eql(u8, last, "wip") and self.include.wip)
                status_is_match = true;
            if (std.mem.eql(u8, last, "go") and self.include.go)
                status_is_match = true;
            if (std.mem.eql(u8, last, "info") and self.include.info)
                status_is_match = true;
            if (std.mem.eql(u8, last, "blocked") and self.include.blocked)
                status_is_match = true;
            if (std.mem.eql(u8, last, "question") and self.include.question)
                status_is_match = true;
            if (std.mem.eql(u8, last, "forward") and self.include.forward)
                status_is_match = true;
            if (std.mem.eql(u8, last, "canceled") and self.include.canceled)
                status_is_match = true;
        }

        if (self.only_def and !has_def)
            return null;
        if (self.only_status and status_is_match == null)
            return null;

        var sum_distance: f64 = 0;
        for (self.parts.items) |q_part| {
            // std.debug.print("Matching '{s}'\n", .{q_part});
            var maybe_min_distance: ?f64 = null;
            if (true) {
                for (aps) |ap| {
                    for (ap.parts.items) |a_part| {
                        var skip_count: usize = undefined;
                        const dist = rubr.fuzz.distance(q_part, a_part.content, &skip_count);
                        // std.debug.print("\t'{s}' '{s}' {} {}\n", .{ q_part, a_part.content, score, skip_count });
                        if (skip_count > 0)
                            continue;
                        maybe_min_distance = @min(dist, maybe_min_distance orelse dist);
                    }
                }
            } else {
                for (chore_parts) |c_part| {
                    if (self.only_def and !c_part.ap.is_definition)
                        continue;

                    // std.debug.print("\t{}\n", .{c_part});
                    for (c_part.ap.parts.items) |a_part| {
                        var skip_count: usize = undefined;
                        const dist = rubr.fuzz.distance(q_part, a_part.content, &skip_count);
                        // std.debug.print("\t'{s}' '{s}' {} {}\n", .{ q_part, a_part.content, score, skip_count });
                        if (skip_count > 0)
                            continue;
                        maybe_min_distance = @min(dist, maybe_min_distance orelse dist);
                    }
                }
            }

            sum_distance += maybe_min_distance orelse return null;
        }

        return sum_distance;
    }
};
