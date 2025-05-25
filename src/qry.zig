const std = @import("std");

const rubr = @import("rubr");

pub const Query = struct {
    const Self = @This();
    pub const Include = struct {
        const My = @This();
        done: bool = false,
        todo: bool = false,
        next: bool = false,
        wip: bool = false,
        question: bool = false,
        callout: bool = false,
        forward: bool = false,

        pub fn set(my: *My, val: bool) void {
            inline for (@typeInfo(My).Struct.fields) |field| {
                @field(my, field.name) = val;
            }
        }
    };

    a: std.mem.Allocator,
    include: Include = .{},

    pub fn init(a: std.mem.Allocator) Self {
        return .{ .a = a };
    }
    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn setup(self: *Self, parts: [][]const u8) !void {
        _ = self;
        for (parts) |part| {
            const strange = rubr.strange.Strange{ .content = part };
            _ = strange;
        }
    }
};
