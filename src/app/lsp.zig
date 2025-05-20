const std = @import("std");

const rubr = @import("rubr");
const Log = rubr.log.Log;
const lsp = rubr.lsp;
const strings = rubr.strings;
const fuzz = rubr.fuzz;

const cfg = @import("../cfg.zig");
const cli = @import("../cli.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");

pub const Error = error{
    ExpectedParams,
    ExpectedQuery,
    ExpectedTextDocument,
    UnexpectedFilenameFormat,
    ExpectedPosition,
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
                            .referencesProvider = true,
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
                    // &cleanup common func between textDocument/definition and textDocument/references
                    // &cleanup by moving some func to Chores

                    if (reloadForest) {
                        self.forest.reinit();
                        try self.forest.load(self.config, self.options);
                        reloadForest = false;
                    }

                    const params = request.params orelse return Error.ExpectedParams;
                    const textdoc = params.textDocument orelse return Error.ExpectedTextDocument;
                    const position = params.position orelse return Error.ExpectedPosition;

                    var aa = std.heap.ArenaAllocator.init(self.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();

                    var src_filename_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const src_filename = try uriToPath_(textdoc.uri, &src_filename_buf, aaa);

                    // Find Amp
                    var maybe_amp: ?amp.Path = null;
                    for (self.forest.chores.list.items) |chore| {
                        if (!std.mem.endsWith(u8, src_filename, chore.path))
                            continue;

                        for (chore.amps.items) |e| {
                            if (e.row == position.line and (e.cols.begin <= position.character and position.character <= e.cols.end)) {
                                maybe_amp = e.path;
                            }
                        }
                    }

                    // Find filename and location of definition
                    var dst_filename: ?[]const u8 = null;
                    var range = dto.Range{};
                    if (maybe_amp) |e| {
                        for (self.forest.chores.defs.items) |def| {
                            if (def.amp.is_fit(e)) {
                                dst_filename = def.path;
                                range.start = dto.Position{ .line = @intCast(def.row), .character = @intCast(def.cols.begin) };
                                range.end = dto.Position{ .line = @intCast(def.row), .character = @intCast(def.cols.end) };
                            }
                        }
                    } else {
                        std.debug.print("Could not find AMP at {s} {}\n", .{ src_filename, position });
                    }

                    if (dst_filename) |filename| {
                        const uri = try pathToUri_(filename, aaa);

                        const location = dto.Location{ .uri = uri, .range = range };

                        try server.send(location);
                    } else {
                        try server.send(null);
                    }
                } else if (request.is("textDocument/references")) {
                    if (reloadForest) {
                        self.forest.reinit();
                        try self.forest.load(self.config, self.options);
                        reloadForest = false;
                    }

                    const params = request.params orelse return Error.ExpectedParams;
                    const textdoc = params.textDocument orelse return Error.ExpectedTextDocument;
                    const position = params.position orelse return Error.ExpectedPosition;

                    var aa = std.heap.ArenaAllocator.init(self.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();

                    var src_filename_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const src_filename = try uriToPath_(textdoc.uri, &src_filename_buf, aaa);

                    // Find Amp
                    var maybe_amp: ?amp.Path = null;
                    for (self.forest.chores.list.items) |chore| {
                        if (!std.mem.endsWith(u8, src_filename, chore.path))
                            continue;

                        for (chore.amps.items) |e| {
                            if (e.row == position.line and (e.cols.begin <= position.character and position.character <= e.cols.end)) {
                                maybe_amp = e.path;
                            }
                        }
                    }

                    // Find all usage locations
                    if (maybe_amp) |a| {
                        var locations = std.ArrayList(dto.Location).init(aaa);
                        for (self.forest.chores.list.items) |e| {
                            for (e.amps.items) |ee| {
                                if (a.is_fit(ee.path)) {
                                    const uri = try pathToUri_(e.path, aaa);
                                    const range = dto.Range{
                                        .start = dto.Position{ .line = @intCast(ee.row), .character = @intCast(ee.cols.begin) },
                                        .end = dto.Position{ .line = @intCast(ee.row), .character = @intCast(ee.cols.end) },
                                    };
                                    const location = dto.Location{ .uri = uri, .range = range };
                                    try locations.append(location);
                                }
                            }
                        }
                        try server.send(locations.items);
                    } else {
                        try server.send(null);
                    }
                } else if (request.is("textDocument/documentSymbol")) {
                    if (reloadForest) {
                        self.forest.reinit();
                        try self.forest.load(self.config, self.options);
                        reloadForest = false;
                    }

                    const params = request.params orelse return Error.ExpectedParams;
                    const textdoc = params.textDocument orelse return Error.ExpectedTextDocument;

                    var aa = std.heap.ArenaAllocator.init(self.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();

                    var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const filename = try uriToPath_(textdoc.uri, &filename_buf, aaa);

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

                        var skip_count: usize = undefined;
                        const score: f32 = @floatCast(fuzz.distance(query, chore.str, &skip_count));

                        if (skip_count == 0) {
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

    // Converts a URI with format 'file:///home/geertf/a%20b.md' into '/home/geert/a b.md'
    fn uriToPath_(uri: []const u8, buf: *[std.fs.max_path_bytes]u8, a: std.mem.Allocator) ![]const u8 {
        const prefix = "file://";

        if (!std.mem.startsWith(u8, uri, prefix))
            return Error.UnexpectedFilenameFormat;

        const size = std.mem.replacementSize(u8, uri[prefix.len..], "%20", " ");

        const b = try a.alloc(u8, size);
        defer a.free(b);

        _ = std.mem.replace(u8, uri[prefix.len..], "%20", " ", b);

        return try std.fs.realpath(b, buf);
    }
    fn pathToUri_(path: []const u8, a: std.mem.Allocator) ![]const u8 {
        const prefix = "file://";
        return try std.mem.concat(a, u8, &[_][]const u8{ prefix, path });
    }
};
