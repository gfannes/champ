const std = @import("std");

const rubr = @import("../rubr.zig");

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");

const Self = @This();

env: rubr.Env,
config: *const cfg.file.Config,
forest: *const mero.Forest,

details: bool = true,

pub fn init(_: *Self) !void {}
pub fn deinit(_: *Self) void {}

pub fn call(self: *Self) !void {
    {
        // var count: usize = 0;
        std.debug.print("WBS markers\n", .{});
        for (self.forest.chores.list.items) |chore| {
            const part_count = if (self.details) chore.parts.items.len else chore.org_count;
            for (chore.parts.items[0..part_count]) |chp| {
                // var is_wbs: bool = false;
                for (chp.ap.parts.items) |app| {
                    _ = app;
                    // &meta &todo
                    // if (app.wbs) |wbs| {
                    //     std.debug.print("WBS {s} {} in {s} {}\n", .{ chore.str, wbs, chore.path, chp.pos });
                    //     count += 1;
                    //     is_wbs = true;
                    // }
                }
                // if (!is_wbs)
                //     std.debug.print("nop {s} {s} {}\n", .{ chore.str, chore.path, chp.pos });
            }
        }
        // std.debug.print("Found {}\n", .{count});
    }
}
