const std = @import("std");

const Log = @import("rubr").log.Log;
const lsp = @import("rubr").lsp;
const strings = @import("rubr").strings;
const fuzz = @import("rubr").fuzz;

const cfg = @import("../cfg.zig");
const cli = @import("../cli.zig");
const mero = @import("../mero.zig");

pub const Error = error{
    ExpectedParams,
    ExpectedQuery,
};

pub const Lsp = struct {
    const Self = @This();

    config: *const cfg.Config,
    options: *const cli.Options,
    log: *const Log,
    a: std.mem.Allocator,

    forest: mero.Forest = undefined,

    pub fn init(self: *Self) !void {
        self.forest = mero.Forest.init(self.log, self.a);
    }
    pub fn deinit(self: *Self) void {
        self.forest.deinit();
    }

    pub fn call(self: *Self) !void {
        try self.log.print("Lsp server started {}\n", .{std.time.timestamp()});

        for (self.config.groves) |cfg_grove| {
            if (!strings.contains(u8, self.options.groves.items, cfg_grove.name))
                // Skip this grove
                continue;
            try self.forest.loadGrove(&cfg_grove);
        }

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
                    const params = request.params orelse return Error.ExpectedParams;
                    const query = params.query orelse return Error.ExpectedQuery;

                    var symbols = std.ArrayList(dto.WorkspaceSymbol).init(self.a);
                    defer symbols.deinit();

                    var aa = std.heap.ArenaAllocator.init(self.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();

                    var iter = self.forest.iter();
                    while (iter.next()) |e| {
                        const score: f32 = @floatCast(fuzz.distance(query, e.name));

                        try symbols.append(dto.WorkspaceSymbol{
                            .name = e.name,
                            .location = dto.Location{
                                .uri = try std.mem.concat(aaa, u8, &[_][]const u8{ "file://", "/", e.path }),
                                .range = dto.Range{
                                    .start = dto.Position{ .line = @intCast(e.line), .character = @intCast(e.start) },
                                    .end = dto.Position{ .line = @intCast(e.line), .character = @intCast(e.end) },
                                },
                            },
                            .score = score,
                        });
                    }

                    const Fn = struct {
                        fn call(_: void, x: dto.WorkspaceSymbol, y: dto.WorkspaceSymbol) bool {
                            const xx = x.score orelse unreachable;
                            const yy = y.score orelse unreachable;
                            return xx < yy;
                        }
                    };
                    std.sort.block(dto.WorkspaceSymbol, symbols.items, {}, Fn.call);

                    try server.send(symbols.items);
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
