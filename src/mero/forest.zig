const std = @import("std");

const Grove = @import("dto.zig").Grove;
const File = @import("dto.zig").File;
const Term = @import("dto.zig").Term;
const cfg = @import("../cfg.zig");

const Log = @import("rubr").log.Log;

pub const Forest = struct {
    const Self = @This();
    const Groves = std.ArrayList(Grove);

    log: *const Log,
    groves: Groves = undefined,
    a: std.mem.Allocator,

    pub fn init(log: *const Log, a: std.mem.Allocator) Self {
        return Self{ .log = log, .groves = Groves.init(a), .a = a };
    }
    pub fn deinit(self: *Self) void {
        self.parser.deinit();
        for (self.groves) |*grove|
            grove.deinit();
        self.groves.deinit();
    }

    pub fn loadGrove(self: *Self, cfg_grove: *const cfg.Grove) !void {
        var grove = try Grove.init(self.log, self.a);
        try grove.load(cfg_grove);
        try self.groves.append(grove);
    }

    pub fn findFile(self: Self, filename: []const u8) ?*const File {
        for (self.groves.items) |grove| {
            for (grove.files.items) |*file| {
                if (std.mem.endsWith(u8, filename, file.path))
                    return file;
                // if (std.mem.eql(u8, file.path, filename))
                //     return file;
            }
        }
        return null;
    }

    pub const Iter = struct {
        pub const Value = struct {
            name: []const u8,
            path: []const u8,
            line: usize,
            start: usize,
            end: usize,
        };

        const LineInfo = struct {
            ix0: usize = 0,
            start: [*]const u8,
        };

        outer: *const Self,
        grove_ix: usize = 0,
        file_ix: usize = 0,
        line_info: ?LineInfo = null,
        term_ix: usize = 0,

        pub fn next(self: *Iter) ?Value {
            while (self.grove_ix < self.outer.groves.items.len) {
                const grove: *const Grove = &self.outer.groves.items[self.grove_ix];
                while (self.file_ix < grove.files.items.len) {
                    const file: *const File = &grove.files.items[self.file_ix];

                    if (self.line_info == null)
                        self.line_info = LineInfo{ .start = file.content.ptr };
                    const line_info: *LineInfo = &(self.line_info orelse unreachable);

                    while (self.term_ix < file.terms.items.len) {
                        const term: *const Term = &file.terms.items[self.term_ix];
                        switch (term.kind) {
                            Term.Kind.Amp => {
                                self.term_ix += 1;
                                const start = term.word.ptr - line_info.start;
                                return Value{
                                    .name = term.word,
                                    .path = file.path,
                                    .line = line_info.ix0,
                                    .start = start,
                                    .end = start + term.word.len,
                                };
                            },
                            Term.Kind.Newline => {
                                self.term_ix += 1;
                                line_info.ix0 += term.word.len;
                                line_info.start = term.word.ptr + term.word.len;
                            },
                            else => {
                                self.term_ix += 1;
                            },
                        }
                    }
                    self.file_ix += 1;
                    self.line_info = null;
                    self.term_ix = 0;
                }
                self.grove_ix += 1;
                self.file_ix = 0;
            }
            return null;
        }
    };

    pub fn iter(self: *const Self) Iter {
        return Iter{ .outer = self };
    }
};
