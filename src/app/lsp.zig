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
                } else if (request.is("textDocument/documentSymbol")) {
                    const params = request.params orelse return Error.ExpectedParams;
                    const textdoc = params.textDocument orelse return Error.ExpectedTextDocument;

                    const prefix = "file://";
                    if (!std.mem.startsWith(u8, textdoc.uri, prefix))
                        return Error.UnexpectedFilenameFormat;

                    var buffer: [std.fs.max_path_bytes]u8 = undefined;
                    const filename = try std.fs.realpath(textdoc.uri[prefix.len..], &buffer);

                    if (reloadForest) {
                        self.forest.reinit();
                        try self.forest.load(self.config, self.options);
                        reloadForest = false;
                    }
                    if (self.forest.findFile(filename)) |file| {
                        var cb = struct {
                            const My = @This();
                            const Symbols = std.ArrayList(dto.DocumentSymbol);

                            aa: std.heap.ArenaAllocator,

                            aaa: std.mem.Allocator = undefined,
                            symbols: Symbols = undefined,
                            is_first: bool = true,

                            fn init(my: *My) void {
                                my.aaa = my.aa.allocator();
                                my.symbols = Symbols.init(my.aaa);
                            }
                            fn deinit(my: *My) void {
                                my.aa.deinit();
                            }

                            pub fn call(my: *My, entry: mero.Tree.Entry) !void {
                                if (my.is_first) {
                                    // Skip first node: this is the File itself, which might contain copied AMPs from the first line.
                                    my.is_first = false;
                                    return;
                                }

                                const n = entry.data;
                                if (!rubr.slice.is_empty(n.orgs.items)) {
                                    // Concat all the orgs into a single 'name'
                                    var name_parts = std.ArrayList([]const u8).init(my.aaa);
                                    var sep: []const u8 = "";
                                    for (n.orgs.items) |org| {
                                        try name_parts.append(try std.fmt.allocPrint(my.aaa, "{s}{}", .{ sep, org }));
                                        sep = " ";
                                    }
                                    const name = try std.mem.concat(my.aaa, u8, name_parts.items);

                                    const range = dto.Range{
                                        .start = dto.Position{ .line = @intCast(n.content_rows.begin), .character = @intCast(n.content_cols.begin) },
                                        .end = dto.Position{ .line = @intCast(n.content_rows.end), .character = @intCast(n.content_cols.end) },
                                    };
                                    try my.symbols.append(dto.DocumentSymbol{
                                        .name = name,
                                        .range = range,
                                        .selectionRange = range,
                                    });
                                }
                            }
                        }{ .aa = std.heap.ArenaAllocator.init(self.a) };
                        cb.init();
                        defer cb.deinit();

                        try self.forest.tree.dfs(file.id, true, &cb);

                        try server.send(cb.symbols.items);
                    } else {
                        try self.log.err("Could not find file {s}\n", .{filename});
                        // &todo: Send error or null
                        try server.send(&[_]dto.DocumentSymbol{});
                    }
                } else if (request.is("workspace/symbol")) {
                    const params = request.params orelse return Error.ExpectedParams;
                    const query = params.query orelse return Error.ExpectedQuery;

                    var cb = struct {
                        const My = @This();
                        const Symbols = std.ArrayList(dto.WorkspaceSymbol);

                        query: []const u8,
                        aa: std.heap.ArenaAllocator,

                        aaa: std.mem.Allocator = undefined,
                        symbols: Symbols = undefined,
                        path: []const u8 = &.{},

                        pub fn init(my: *My) void {
                            my.aaa = my.aa.allocator();
                            my.symbols = Symbols.init(my.aaa);
                        }
                        pub fn deinit(my: *@This()) void {
                            my.aa.deinit();
                        }

                        pub fn call(my: *@This(), entry: mero.Tree.Entry) !void {
                            const n = entry.data;
                            switch (n.type) {
                                mero.Node.Type.Grove => {},
                                mero.Node.Type.Folder => {},
                                mero.Node.Type.File => {
                                    my.path = n.path;
                                },
                                else => {
                                    if (!rubr.slice.is_empty(n.orgs.items)) {
                                        var name_parts = std.ArrayList([]const u8).init(my.aaa);
                                        var sep: []const u8 = "";
                                        for (n.orgs.items) |org| {
                                            try name_parts.append(try std.fmt.allocPrint(my.aaa, "{s}{}", .{ sep, org }));
                                            sep = " ";
                                        }
                                        const name = try std.mem.concat(my.aaa, u8, name_parts.items);

                                        const score: f32 = @floatCast(fuzz.distance(my.query, name));

                                        const range = dto.Range{
                                            .start = dto.Position{ .line = @intCast(n.content_rows.begin), .character = @intCast(n.content_cols.begin) },
                                            .end = dto.Position{ .line = @intCast(n.content_rows.end), .character = @intCast(n.content_cols.end) },
                                        };
                                        try my.symbols.append(dto.WorkspaceSymbol{
                                            .name = name,
                                            .location = dto.Location{
                                                .uri = try std.mem.concat(my.aaa, u8, &[_][]const u8{ "file://", "/", my.path }),
                                                .range = range,
                                            },
                                            .score = score,
                                        });
                                    }
                                },
                            }
                        }
                    }{
                        .query = query,
                        .aa = std.heap.ArenaAllocator.init(self.a),
                    };
                    cb.init();
                    defer cb.deinit();

                    if (reloadForest) {
                        self.forest.reinit();
                        try self.forest.load(self.config, self.options);
                        reloadForest = false;
                    }
                    try self.forest.tree.dfsAll(true, &cb);

                    const ByScore = struct {
                        fn call(_: void, x: dto.WorkspaceSymbol, y: dto.WorkspaceSymbol) bool {
                            const xx = x.score orelse unreachable;
                            const yy = y.score orelse unreachable;
                            return xx < yy;
                        }
                    };
                    std.sort.block(dto.WorkspaceSymbol, cb.symbols.items, {}, ByScore.call);

                    try server.send(cb.symbols.items);
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
