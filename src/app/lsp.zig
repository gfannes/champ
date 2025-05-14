const std = @import("std");

const rubr = @import("rubr");
const Log = rubr.log.Log;
const lsp = rubr.lsp;
const strings = rubr.strings;
const fuzz = rubr.fuzz;

const cfg = @import("../cfg.zig");
const cli = @import("../cli.zig");
const mero = @import("../mero.zig");

pub const Error = error{
    ExpectedParams,
    ExpectedQuery,
    ExpectedTextDocument,
    UnexpectedFilenameFormat,
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
        try self.log.info("Lsp server started {}\n", .{std.time.timestamp()});

        var cin = std.io.getStdIn();
        var cout = std.io.getStdOut();

        var server = lsp.Server.init(cin.reader(), cout.writer(), self.log.writer(), self.a);
        defer server.deinit();

        var reloadForest: bool = true;

        var count: usize = 0;
        var do_continue = true;
        var init_ok = false;
        while (do_continue) : (count += 1) {
            try self.log.info("[Iteration](count:{})\n", .{count});

            const request = try server.receive();
            const dto = lsp.dto;
            if (request.id) |_| {
                if (request.is("initialize")) {
                    try self.forest.load(self.config, self.options);
                    reloadForest = false;

                    const result = dto.InitializeResult{
                        .capabilities = dto.ServerCapabilities{
                            .textDocumentSync = dto.ServerCapabilities.TextDocumentSyncOptions{},
                            .documentSymbolProvider = true,
                            .workspaceSymbolProvider = true,
                            .definitionProvider = true,
                            .workspace = dto.ServerCapabilities.Workspace{
                                .workspaceFolders = dto.ServerCapabilities.Workspace.WorkspaceFolders{
                                    .supported = true,
                                },
                            },
                        },
                        .serverInfo = dto.ServerInfo{
                            // &:zig:build:info Couple this with info from build.zig.zon
                            .name = "champ",
                            .version = "0.0.1",
                        },
                    };
                    try server.send(result);
                } else if (request.is("shutdown")) {
                    try server.send(null);
                } else if (request.is("textDocument/definition")) {
                    var aa = std.heap.ArenaAllocator.init(self.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();

                    const prefix = "file://";
                    const filename = "/home/geertf/gubg/rakefile.rb";
                    const uri = try std.mem.concat(aaa, u8, &[_][]const u8{ prefix, filename });

                    const range = dto.Range{
                        .start = dto.Position{ .line = 0, .character = 0 },
                        .end = dto.Position{ .line = 1, .character = 0 },
                    };

                    const location = dto.Location{ .uri = uri, .range = range };

                    try server.send(location);
                } else if (request.is("textDocument/documentSymbol")) {
                    if (reloadForest) {
                        self.forest.reinit();
                        try self.forest.load(self.config, self.options);
                        reloadForest = false;
                    }

                    const params = request.params orelse return Error.ExpectedParams;
                    const textdoc = params.textDocument orelse return Error.ExpectedTextDocument;

                    const prefix = "file://";
                    if (!std.mem.startsWith(u8, textdoc.uri, prefix))
                        return Error.UnexpectedFilenameFormat;

                    var buffer: [std.fs.max_path_bytes]u8 = undefined;
                    const filename = try std.fs.realpath(textdoc.uri[prefix.len..], &buffer);

                    var aa = std.heap.ArenaAllocator.init(self.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();
                    var document_symbols = std.ArrayList(dto.DocumentSymbol).init(aaa);

                    for (self.forest.chores.list.items) |chore| {
                        if (!std.mem.endsWith(u8, filename, chore.path))
                            continue;

                        if (rubr.slice.is_empty(chore.amps.items)) {
                            try self.log.warning("Expected to find at least one AMP for Chore\n", .{});
                            continue;
                        }

                        const first_amp = &chore.amps.items[0];
                        const last_amp = &chore.amps.items[chore.amps.items.len - 1];
                        const range = dto.Range{
                            .start = dto.Position{ .line = @intCast(first_amp.row), .character = @intCast(first_amp.cols.begin) },
                            .end = dto.Position{ .line = @intCast(last_amp.row), .character = @intCast(last_amp.cols.end) },
                        };
                        try document_symbols.append(dto.DocumentSymbol{
                            .name = chore.str,
                            .range = range,
                            .selectionRange = range,
                        });
                    }

                    try server.send(document_symbols.items);
                } else if (request.is("workspace/symbol")) {
                    if (reloadForest) {
                        self.forest.reinit();
                        try self.forest.load(self.config, self.options);
                        reloadForest = false;
                    }

                    const params = request.params orelse return Error.ExpectedParams;
                    const query = params.query orelse return Error.ExpectedQuery;

                    var aa = std.heap.ArenaAllocator.init(self.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();
                    var workspace_symbols = std.ArrayList(dto.WorkspaceSymbol).init(aaa);

                    for (self.forest.chores.list.items) |chore| {
                        if (rubr.slice.is_empty(chore.amps.items)) {
                            try self.log.warning("Expected to find at least one AMP per Chore\n", .{});
                            continue;
                        }

                        const score: f32 = @floatCast(fuzz.distance(query, chore.str));

                        const first_amp = &chore.amps.items[0];
                        const last_amp = &chore.amps.items[chore.amps.items.len - 1];
                        const range = dto.Range{
                            .start = dto.Position{ .line = @intCast(first_amp.row), .character = @intCast(first_amp.cols.begin) },
                            .end = dto.Position{ .line = @intCast(last_amp.row), .character = @intCast(last_amp.cols.end) },
                        };
                        try workspace_symbols.append(dto.WorkspaceSymbol{
                            .name = chore.str,
                            .location = dto.Location{
                                .uri = try std.mem.concat(aaa, u8, &[_][]const u8{ "file://", "/", chore.path }),
                                .range = range,
                            },
                            .score = score,
                        });
                    }

                    const ByScore = struct {
                        fn call(_: void, x: dto.WorkspaceSymbol, y: dto.WorkspaceSymbol) bool {
                            const xx = x.score orelse unreachable;
                            const yy = y.score orelse unreachable;
                            return xx < yy;
                        }
                    };
                    std.sort.block(dto.WorkspaceSymbol, workspace_symbols.items, {}, ByScore.call);

                    try server.send(workspace_symbols.items);
                } else {
                    try self.log.warning("Unhandled request '{s}'\n", .{request.method});
                }
            } else {
                if (request.is("textDocument/didOpen")) {
                    //
                } else if (request.is("textDocument/didChange")) {
                    reloadForest = true;
                } else if (request.is("initialized")) {
                    init_ok = true;
                } else if (request.is("exit")) {
                    do_continue = false;
                } else {
                    try self.log.warning("Unhandled notification '{s}'\n", .{request.method});
                }
            }
        }
    }
};
