const std = @import("std");

const Log = @import("rubr").log.Log;

const cfg = @import("../cfg.zig");
const cli = @import("../cli.zig");
const lsp = @import("../lsp.zig");

pub const Lsp = struct {
    const Self = @This();

    config: *const cfg.Config,
    options: *const cli.Options,
    log: *const Log,
    a: std.mem.Allocator,

    pub fn call(self: Self) !void {
        try self.log.print("Lsp server started {}\n", .{std.time.timestamp()});

        var cin = std.io.getStdIn();
        var cout = std.io.getStdOut();

        var server = lsp.Server.init(cin.reader(), cout.writer(), self.log.writer(), self.a);
        defer server.deinit();

        var count: usize = 0;
        var do_continue = true;
        var init_ok = false;
        while (do_continue) : (count += 1) {
            try self.log.print("[Iteration](count:{})\n", .{count});

            const request = try server.receive();
            const dto = lsp.dto;
            if (request.id) |_| {
                if (std.mem.eql(u8, request.method, "initialize")) {
                    const result = dto.InitializeResult{
                        .capabilities = dto.ServerCapabilities{
                            .documentSymbolProvider = true,
                            .workspaceSymbolProvider = true,
                        },
                        .serverInfo = dto.ServerInfo{
                            .name = "chimp",
                            .version = "1.2.3",
                        },
                    };
                    try server.send(result);
                } else if (std.mem.eql(u8, request.method, "shutdown")) {
                    try server.send(null);
                } else if (std.mem.eql(u8, request.method, "textDocument/documentSymbol")) {
                    // &todo replace with actual symbols. Workspace symbols seems to not work in Helix.
                    const symbols = [_]dto.DocumentSymbol{ .{ .name = "abc" }, .{ .name = "def", .kind = 5 } };
                    try server.send(symbols);
                } else {
                    try self.log.print("Unhandled request '{s}'\n", .{request.method});
                }
            } else {
                if (std.mem.eql(u8, request.method, "textDocument/didOpen")) {
                    //
                } else if (std.mem.eql(u8, request.method, "initialized")) {
                    init_ok = true;
                } else if (std.mem.eql(u8, request.method, "exit")) {
                    do_continue = false;
                } else {
                    try self.log.print("Unhandled notification '{s}'\n", .{request.method});
                }
            }
        }
    }
};
