const std = @import("std");

const rubr = @import("rubr");

const Chore = @import("chore.zig").Chore;

pub const Query = struct {
    const Self = @This();
    const Parts = std.ArrayList([]const u8);
    pub const Include = struct {
        const My = @This();
        done: bool = false,
        todo: bool = false,
        next: bool = false,
        wip: bool = false,
        canceled: bool = false,
        question: bool = false,
        callout: bool = false,
        forward: bool = false,

        pub fn set(my: *My, val: bool) void {
            inline for (@typeInfo(My).@"struct".fields) |field|
                @field(my, field.name) = val;
        }
        pub fn all(my: My, val: bool) bool {
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
    parts: Parts,

    pub fn init(a: std.mem.Allocator) Self {
        return .{ .a = a, .parts = Parts.init(a) };
    }
    pub fn deinit(self: *Self) void {
        for (self.parts.items) |part|
            self.a.free(part);
        self.parts.deinit();
    }

    pub fn setup(self: *Self, parts: []const []const u8) !void {
        for (parts) |part| {
            var strange = rubr.strng.Strange{ .content = part };

            while (!strange.empty()) {
                if (strange.popChar('.')) {
                    self.include.set(true);
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
                    self.include.next = true;
                    self.only_status = true;
                } else if (strange.popChar('-')) {
                    self.include.canceled = true;
                    self.only_status = true;
                } else if (strange.popChar('!')) {
                    self.include.callout = true;
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
                    try self.parts.append(try self.a.dupe(u8, str));
            }
        }

        if (self.include.all(false)) {
            self.include.set(true);
            self.include.done = false;
        }
    }

    pub fn distance(self: Self, chore: Chore) ?f64 {
        const status_is_match = block: {
            for (chore.parts.items) |part| {
                const last = rubr.lastPtrUnsafe(part.ap.parts.items).content;
                if (std.mem.eql(u8, last, "done"))
                    break :block self.include.done;
                if (std.mem.eql(u8, last, "todo"))
                    break :block self.include.todo;
                if (std.mem.eql(u8, last, "wip"))
                    break :block self.include.wip;
                if (std.mem.eql(u8, last, "next"))
                    break :block self.include.next;
                if (std.mem.eql(u8, last, "callout"))
                    break :block self.include.callout;
                if (std.mem.eql(u8, last, "question"))
                    break :block self.include.question;
                if (std.mem.eql(u8, last, "forward"))
                    break :block self.include.forward;
                if (std.mem.eql(u8, last, "canceled"))
                    break :block self.include.canceled;
            }
            break :block !self.only_status;
        };
        if (!status_is_match)
            return null;

        var sum_score: f64 = 0;
        for (self.parts.items) |q_part| {
            // std.debug.print("Matching '{s}'\n", .{q_part});
            var maybe_min_score: ?f64 = null;
            for (chore.parts.items) |c_part| {
                // std.debug.print("\t{}\n", .{c_part});
                for (c_part.ap.parts.items) |a_part| {
                    var skip_count: usize = undefined;
                    const score = rubr.fuzz.distance(q_part, a_part.content, &skip_count);
                    // std.debug.print("\t'{s}' {} {}\n", .{ a_part.content, score, skip_count });
                    if (skip_count > 0)
                        continue;
                    if (maybe_min_score) |*min_score| {
                        min_score.* = @min(min_score.*, score);
                    } else {
                        maybe_min_score = score;
                    }
                }
            }

            if (maybe_min_score) |min_score| {
                sum_score += min_score;
            } else {
                // std.debug.print("Could not match '{s}'\n", .{q_part});
                return null;
            }
        }

        return sum_score;
    }
};
