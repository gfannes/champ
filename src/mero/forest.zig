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

    pub const Iter = struct {
        pub const Value = struct {
            name: []const u8,
            path: []const u8,
        };

        outer: *const Self,
        grove_ix: usize = 0,
        file_ix: usize = 0,
        term_ix: usize = 0,

        pub fn next(self: *Iter) ?Value {
            while (self.grove_ix < self.outer.groves.items.len) {
                const grove: *const Grove = &self.outer.groves.items[self.grove_ix];
                while (self.file_ix < grove.files.items.len) {
                    const file: *const File = &grove.files.items[self.file_ix];
                    while (self.term_ix < file.terms.items.len) {
                        const term: *const Term = &file.terms.items[self.term_ix];
                        switch (term.kind) {
                            Term.Kind.Amp => {
                                self.term_ix += 1;
                                return Value{ .name = term.word, .path = file.path };
                            },
                            else => {
                                self.term_ix += 1;
                            },
                        }
                    }
                    self.file_ix += 1;
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
