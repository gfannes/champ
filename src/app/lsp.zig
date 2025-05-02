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
        try self.log.print("Lsp server started {}\n", .{std.time.timestamp()});

        try self.forest.load(self.config, self.options);

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
                    const params = request.params orelse return Error.ExpectedParams;
                    const textdoc = params.textDocument orelse return Error.ExpectedTextDocument;

                    const prefix = "file://";
                    if (!std.mem.startsWith(u8, textdoc.uri, prefix))
                        return Error.UnexpectedFilenameFormat;

                    var buffer: [std.fs.max_path_bytes]u8 = undefined;
                    const filename = try std.fs.realpath(textdoc.uri[prefix.len..], &buffer);

                    if (self.forest.findFile(filename)) |file| {
                        var symbols = std.ArrayList(dto.DocumentSymbol).init(self.a);
                        defer symbols.deinit();

                        var line: usize = 0;
                        for (file.terms.items) |term| {
                            switch (term.kind) {
                                mero.Term.Kind.Newline => line += term.word.len,
                                mero.Term.Kind.Amp => {
                                    const start = term.word.ptr - file.content.ptr;

                                    try symbols.append(dto.DocumentSymbol{
                                        .name = term.word,
                                        .range = dto.Range{
                                            .start = dto.Position{ .line = @intCast(line), .character = @intCast(start) },
                                            .end = dto.Position{ .line = @intCast(line), .character = @intCast(start + term.word.len) },
                                        },
                                        .selectionRange = dto.Range{
                                            .start = dto.Position{ .line = @intCast(line), .character = @intCast(start) },
                                            .end = dto.Position{ .line = @intCast(line), .character = @intCast(start + term.word.len) },
                                        },
                                    });
                                },
                                else => {},
                            }
                        }
                        try server.send(symbols.items);
                    } else {
                        try self.log.print("Error: could not find file {s}\n", .{filename});
                        // &todo: Send error or null
                        try server.send(&[_]dto.DocumentSymbol{});
                    }
                } else if (request.is("workspace/symbol")) {
                    const params = request.params orelse return Error.ExpectedParams;
                    const query = params.query orelse return Error.ExpectedQuery;

                    var cb = struct {
                        const Symbols = std.ArrayList(dto.WorkspaceSymbol);

                        query: []const u8,
                        symbols: Symbols,
                        aa: std.heap.ArenaAllocator,

                        pub fn init(q: []const u8, a: std.mem.Allocator) @This() {
                            return @This(){
                                .query = q,
                                .symbols = Symbols.init(a),
                                .aa = std.heap.ArenaAllocator.init(a),
                            };
                        }
                        pub fn deinit(my: *@This()) void {
                            my.symbols.deinit();
                            my.aa.deinit();
                        }

                        pub fn call(my: *@This(), entry: mero.Tree.Entry) !void {
                            const n = entry.data;
                            if (n.type) |typ| {
                                if (typ == mero.Node.Type.File) {
                                    var line: usize = 0;
                                    for (n.terms.items) |term| {
                                        switch (term.kind) {
                                            mero.Term.Kind.Newline => line += term.word.len,
                                            mero.Term.Kind.Amp => {
                                                const score: f32 = @floatCast(fuzz.distance(my.query, term.word));
                                                const start = term.word.ptr - n.content.ptr;

                                                const aaa = my.aa.allocator();
                                                try my.symbols.append(dto.WorkspaceSymbol{
                                                    .name = term.word,
                                                    .location = dto.Location{
                                                        .uri = try std.mem.concat(aaa, u8, &[_][]const u8{ "file://", "/", n.path }),
                                                        .range = dto.Range{
                                                            .start = dto.Position{ .line = @intCast(line), .character = @intCast(start) },
                                                            .end = dto.Position{ .line = @intCast(line), .character = @intCast(start + term.word.len) },
                                                        },
                                                    },
                                                    .score = score,
                                                });
                                            },
                                            else => {},
                                        }
                                    }
                                }
                            }
                        }
                    }.init(query, self.a);
                    defer cb.deinit();

                    try self.forest.tree.dfs(true, &cb);

                    const Fn = struct {
                        fn call(_: void, x: dto.WorkspaceSymbol, y: dto.WorkspaceSymbol) bool {
                            const xx = x.score orelse unreachable;
                            const yy = y.score orelse unreachable;
                            return xx < yy;
                        }
                    };
                    std.sort.block(dto.WorkspaceSymbol, cb.symbols.items, {}, Fn.call);

                    try server.send(cb.symbols.items);
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
