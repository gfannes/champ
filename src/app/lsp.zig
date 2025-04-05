const std = @import("std");

const Log = @import("rubr").log.Log;
const lsp = @import("rubr").lsp;

const cfg = @import("../cfg.zig");
const cli = @import("../cli.zig");
const mero = @import("../mero.zig");

pub const Lsp = struct {
    const Self = @This();

    config: *const cfg.Config,
    options: *const cli.Options,
    log: *const Log,
    a: std.mem.Allocator,

    forest: mero.Forest = undefined,

    pub fn init(self: *Self) !void {
        self.forest = mero.Forest.init(self.a);
    }
    pub fn deinit(self: *Self) void {
        self.forest.deinit();
    }

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
                if (request.is("initialize")) {
                    const result = dto.InitializeResult{
                        .capabilities = dto.ServerCapabilities{
                            .documentSymbolProvider = true,
                            .workspaceSymbolProvider = true,
                            .workspace = dto.ServerCapabilities.Workspace{
                                .workspaceFolders = dto.ServerCapabilities.Workspace.WorkspaceFolders{
                                    .supported = true,
                                },
                            },
                        },
                        .serverInfo = dto.ServerInfo{
                            .name = "chimp",
                            .version = "1.2.3",
                        },
                    };
                    try server.send(result);
                } else if (request.is("shutdown")) {
                    try server.send(null);
                } else if (request.is("textDocument/documentSymbol")) {
                    // &todo replace with actual symbols. Workspace symbols seems to not work in Helix.
                    const symbols = [_]dto.DocumentSymbol{ .{ .name = "document property" }, .{ .name = "document class", .kind = 5 } };
                    try server.send(symbols);
                } else if (request.is("workspace/symbol")) {
                    const symbols = [_]dto.WorkspaceSymbol{
                        .{
                            .name = "workspace property",
                            .location = .{ .uri = "file:///home/geertf/chimp/test.chimp" },
                            .score = 0.2,
                        },
                        .{
                            .name = "workspace class",
                            .kind = 5,
                            .location = .{ .uri = "file:///home/geertf/chimp/rakefile.rb" },
                            // .score = 0.1,
                        },
                    };
                    try server.send(symbols);
                } else {
                    try self.log.print("Unhandled request '{s}'\n", .{request.method});
                }
            } else {
                if (request.is("textDocument/didOpen")) {
                    //
                } else if (request.is("initialized")) {
                    init_ok = true;
                } else if (request.is("exit")) {
                    do_continue = false;
                } else {
                    try self.log.print("Unhandled notification '{s}'\n", .{request.method});
                }
            }
        }
    }
};
