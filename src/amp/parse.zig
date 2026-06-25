const std = @import("std");
const rubr = @import("../rubr.zig");

const Meta = @import("Meta.zig");
const Path = @import("Path.zig");

pub const Error = error{
    InvalidCost,
    InvalidPrio,
    InvalidWorker,
    InvalidWbs,
};

pub fn parse(strange: *rubr.strng.Strange, meta: *Meta) !?Path {
    if (strange.popChar('&')) {
        var is_exclusive = strange.popChar('^');

        if (strange.popChar('$')) {
            meta.cost = Meta.Cost{ .value = strange.popInt(u32) orelse return error.InvalidCost };
            return null;
        } else if (strange.popChar('#')) {
            const relative = if (strange.front()) |ch| ch == '+' or ch == '-' else false;
            meta.order = Meta.Order{ .value = strange.popInt(i32) orelse return error.InvalidOrder, .relative = relative, .is_exclusive = is_exclusive };
            return null;
        } else if (strange.popChar('@')) {
            const name = strange.popAll() orelse return error.InvalidWorker;
            try meta.appendWorker(Meta.Worker{ .name = name });
            var path = Path.init(meta.a);
            errdefer path.deinit();
            try path.parts.append(path.a, .{ .content = "worker" });
            try path.parts.append(path.a, .{ .content = name });
            return path;
        } else if (strange.popChar('?')) {
            meta.wbs = Meta.Wbs.parse(strange.str(), .{});
            return null;
        } else if (Meta.Date.parse(strange.str(), .{})) |date| {
            meta.date = date;
            return null;
        } else if (Meta.Status.fromLower(strange.str())) |status| {
            meta.status = status;
            return null;
        } else {
            var path = Path.init(meta.a);
            errdefer path.deinit();
            path.is_definition = strange.popChar('&');
            path.is_absolute = strange.popChar(':');

            while (strange.popCharBack(':')) {}
            path.is_dependency = strange.popCharBack('&');

            while (!strange.empty()) {
                var maybe_content = strange.popTo(':');
                if (maybe_content == null)
                    maybe_content = strange.popAll();

                if (maybe_content) |content| {
                    try path.parts.append(path.a, Path.Part{ .content = content, .is_exclusive = is_exclusive });

                    is_exclusive = strange.popChar('^');
                }
            }

            return path;
        }
    } else if (strange.popStr("[[") and strange.popStrBack("]]")) {
        var path = Path.init(meta.a);
        errdefer path.deinit();

        try path.parts.append(path.a, Path.Part{ .content = strange.str() });

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
                if (Meta.Status.fromLower(content)) |status| {
                    meta.status = status;
                    return null;
                }
            }
        }
    } else if (Meta.Status.fromCapital(strange.str())) |status| {
        meta.status = status;
        return null;
    }

    return error.ExpectedAmp;
}
