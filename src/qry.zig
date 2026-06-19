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
    worker: ?[]const u8 = null,
    parts: Parts = .empty,
    aps: std.ArrayList(*const amp.Path) = .empty,
    chore: ?Chore = null,

    do_log: bool = false,

    pub fn deinit(self: *Self) void {
        for (self.parts.items) |part|
            self.a.free(part);
        self.parts.deinit(self.a);
        self.aps.deinit(self.a);
    }

    pub fn setup(self: *Self, parts: []const []const u8) !void {
        for (parts) |part| {
            if (self.do_log)
                std.debug.print("part: '{s}'\n", .{part});
            var strange = rubr.strng.Strange{ .content = part };

            while (!strange.empty()) {
                if (strange.popChar('.')) {
                    self.include.set_all(true);
                    self.only_status = true;
                } else if (strange.popStr("[ ]") or strange.popChar(' ') or strange.popChar(',')) {
                    self.include.todo = true;
                    self.only_status = true;
                } else if (strange.popStr("[x]")) {
                    self.include.done = true;
                    self.only_status = true;
                } else if (strange.popStr("[/]") or strange.popChar('/')) {
                    self.include.wip = true;
                    self.only_status = true;
                } else if (strange.popStr("[*]") or strange.popChar('*')) {
                    self.include.go = true;
                    self.only_status = true;
                } else if (strange.popStr("[-]") or strange.popChar('-')) {
                    self.include.canceled = true;
                    self.only_status = true;
                } else if (strange.popStr("[i]")) {
                    self.include.info = true;
                    self.only_status = true;
                } else if (strange.popStr("[!]") or strange.popChar('!')) {
                    self.include.blocked = true;
                    self.only_status = true;
                } else if (strange.popStr("[?]") or strange.popChar('?')) {
                    self.include.question = true;
                    self.only_status = true;
                } else if (strange.popStr("[>]") or strange.popChar('>')) {
                    self.include.forward = true;
                    self.only_status = true;
                } else if (strange.popChar('@')) {
                    self.worker = strange.popAll();
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

    // Call this to reset this Query instance to start the computation of a match with a new Chore
    pub fn prepare(self: *Self, chore: Chore) !void {
        try self.aps.resize(self.a, 0);
        self.chore = chore;
    }

    // Add all relevant amp.Paths that you want to consider for matching
    pub fn add(self: *Self, ap: *const amp.Path) !void {
        try self.aps.append(self.a, ap);
    }

    // Compute the match itself
    pub fn distance(self: Self) ?f64 {
        const chore = self.chore orelse return null;

        var status_is_match: ?bool = null;
        if (chore.meta.status) |status| {
            if (status.kind == .Done and self.include.done)
                status_is_match = true;
            if (status.kind == .Todo and self.include.todo)
                status_is_match = true;
            if (status.kind == .Wip and self.include.wip)
                status_is_match = true;
            if (status.kind == .Go and self.include.go)
                status_is_match = true;
            if (status.kind == .Info and self.include.info)
                status_is_match = true;
            if (status.kind == .Blocked and self.include.blocked)
                status_is_match = true;
            if (status.kind == .Question and self.include.question)
                status_is_match = true;
            if (status.kind == .Forward and self.include.forward)
                status_is_match = true;
            if (status.kind == .Canceled and self.include.canceled)
                status_is_match = true;
        }

        if (self.do_log)
            std.debug.print("{} {?} worker {?s}\n", .{ self.only_status, status_is_match, self.worker });
        if (self.only_status and status_is_match == null)
            return null;

        var worker_matches: bool = false;
        if (self.worker) |worker| {
            for (chore.meta.workers.items) |w| {
                if (std.mem.eql(u8, w.name, worker))
                    worker_matches = true;
            }
        } else {
            worker_matches = rubr.slc.isEmpty(chore.meta.workers.items);
        }
        if (!worker_matches)
            return null;

        var sum_distance: f64 = 0;
        if (self.do_log)
            std.debug.print("{}\n", .{self.parts.items.len});
        for (self.parts.items) |q_part| {
            if (self.do_log)
                std.debug.print("Matching '{s}'\n", .{q_part});
            var maybe_min_distance: ?f64 = null;
            for (self.aps.items) |ap| {
                for (ap.parts.items) |a_part| {
                    var skip_count: usize = undefined;
                    const dist = rubr.fuzz.distance(q_part, a_part.content, &skip_count);
                    if (self.do_log)
                        std.debug.print("\t'{s}' '{s}' {} {}\n", .{ q_part, a_part.content, dist, skip_count });
                    if (skip_count > 0)
                        continue;
                    maybe_min_distance = @min(dist, maybe_min_distance orelse dist);
                }
            }

            sum_distance += maybe_min_distance orelse return null;
        }

        return sum_distance;
    }
};
