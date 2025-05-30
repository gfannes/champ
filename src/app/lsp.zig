const std = @import("std");
const builtin = @import("builtin");

const rubr = @import("rubr");
const Log = rubr.log.Log;
const lsp = rubr.lsp;
const strings = rubr.strings;
const fuzz = rubr.fuzz;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");
const qry = @import("../qry.zig");

pub const Error = error{
    ExpectedParams,
    ExpectedQuery,
    ExpectedTextDocument,
    UnexpectedFilenameFormat,
    ExpectedPosition,
    CouldNotLoadConfig,
};

pub const Lsp = struct {
    const Self = @This();

    config: *const cfg.file.Config,
    options: *const cfg.cli.Options,
    log: *const Log,
    a: std.mem.Allocator,

    forest_pp: ForestPP = undefined,

    pub fn init(self: *Self) !void {
        self.forest_pp = ForestPP.init(self.options, self.log, self.a);
    }
    pub fn deinit(self: *Self) void {
        self.forest_pp.deinit();
    }

    pub fn call(self: *Self) !void {
        try self.log.info("Lsp server started {}\n", .{std.time.timestamp()});

        var cin = std.io.getStdIn();
        var cout = std.io.getStdOut();

        var server = lsp.Server.init(cin.reader(), cout.writer(), self.log.writer(), self.a);
        defer server.deinit();

        var reloadForest: bool = true;

        try self.forest_pp.startThread();

        var count: usize = 0;
        var do_continue = true;
        var init_ok = false;
        while (do_continue) : (count += 1) {
            try self.log.info("[Iteration](count:{})\n", .{count});

            self.forest_pp.mutex.lock();
            defer self.forest_pp.mutex.unlock();
            const forest = self.forest_pp.ping();

            const request = try server.receive();
            const dto = lsp.dto;
            if (request.id) |_| {
                if (request.is("initialize")) {
                    try forest.load(self.config, self.options);
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
                        forest.reinit();
                        try forest.load(self.config, self.options);
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
                    var maybe_ap: ?amp.Path = null;
                    for (forest.chores.list.items) |chore| {
                        if (!std.mem.endsWith(u8, src_filename, chore.path))
                            continue;

                        for (chore.parts.items) |part| {
                            if (part.row == position.line and (part.cols.begin <= position.character and position.character <= part.cols.end)) {
                                maybe_ap = part.ap;
                            }
                        }
                    }

                    // Find filename and location of definition
                    var dst_filename: ?[]const u8 = null;
                    var range = dto.Range{};
                    if (maybe_ap) |e| {
                        for (forest.chores.defs.items) |def| {
                            if (def.ap.is_fit(e)) {
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
                        forest.reinit();
                        try forest.load(self.config, self.options);
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
                    var maybe_ap: ?amp.Path = null;
                    for (forest.chores.list.items) |chore| {
                        if (!std.mem.endsWith(u8, src_filename, chore.path))
                            continue;

                        for (chore.parts.items) |part| {
                            if (part.row == position.line and (part.cols.begin <= position.character and position.character <= part.cols.end)) {
                                maybe_ap = part.ap;
                            }
                        }
                    }

                    // Find all usage locations
                    if (maybe_ap) |ap| {
                        var locations = std.ArrayList(dto.Location).init(aaa);
                        for (forest.chores.list.items) |e| {
                            for (e.parts.items) |part| {
                                if (ap.is_fit(part.ap)) {
                                    const uri = try pathToUri_(e.path, aaa);
                                    const range = dto.Range{
                                        .start = dto.Position{ .line = @intCast(part.row), .character = @intCast(part.cols.begin) },
                                        .end = dto.Position{ .line = @intCast(part.row), .character = @intCast(part.cols.end) },
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
                        forest.reinit();
                        try forest.load(self.config, self.options);
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

                    for (forest.chores.list.items) |chore| {
                        if (!std.mem.endsWith(u8, filename, chore.path))
                            continue;

                        if (rubr.slice.is_empty(chore.parts.items)) {
                            try self.log.warning("Expected to find at least one AMP for Chore\n", .{});
                            continue;
                        }

                        const first_amp = &chore.parts.items[0];
                        const last_amp = &chore.parts.items[chore.org_count - 1];
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
                        forest.reinit();
                        try forest.load(self.config, self.options);
                        reloadForest = false;
                    }

                    const params = request.params orelse return Error.ExpectedParams;
                    const query = params.query orelse return Error.ExpectedQuery;

                    var aa = std.heap.ArenaAllocator.init(self.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();
                    var workspace_symbols = std.ArrayList(dto.WorkspaceSymbol).init(aaa);

                    var q = qry.Query.init(self.a);
                    defer q.deinit();
                    try q.setup(&[_][]const u8{query});

                    for (forest.chores.list.items) |chore| {
                        if (rubr.slice.is_empty(chore.parts.items)) {
                            try self.log.warning("Expected to find at least one AMP per Chore\n", .{});
                            continue;
                        }

                        if (q.distance(chore)) |distance| {
                            const first_amp = &chore.parts.items[0];
                            const last_amp = &chore.parts.items[chore.org_count - 1];
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
                                .score = @floatCast(distance),
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

                    const size = @min(workspace_symbols.items.len, self.config.lsp.max_array_size);

                    try server.send(workspace_symbols.items[0..size]);
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

pub const ForestPP = struct {
    const Self = @This();

    options: *const cfg.cli.Options,

    a: std.mem.Allocator,
    config_loader: cfg.file.Loader,

    mutex: std.Thread.Mutex = .{},

    thread: ?std.Thread = null,
    quit_thread: bool = false,

    pp: [2]mero.Forest,
    ping_is_first: bool = true,

    pub fn init(options: *const cfg.cli.Options, log: *const rubr.log.Log, a: std.mem.Allocator) ForestPP {
        return ForestPP{ .options = options, .a = a, .config_loader = try cfg.file.Loader.init(a), .pp = .{ mero.Forest.init(log, a), mero.Forest.init(log, a) } };
    }
    pub fn deinit(self: *Self) void {
        self.stopThread();
        self.config_loader.deinit();
        for (&self.pp) |*forest|
            forest.deinit();
    }

    pub fn ping(self: *Self) *mero.Forest {
        return &self.pp[if (self.ping_is_first) 0 else 1];
    }
    pub fn pong(self: *Self) *mero.Forest {
        return &self.pp[if (self.ping_is_first) 1 else 0];
    }

    pub fn swap(self: *Self) void {
        self.ping_is_first = !self.ping_is_first;
    }

    fn startThread(self: *Self) !void {
        self.stopThread();
        self.quit_thread = false;
        self.thread = try std.Thread.spawn(.{}, Self.call, .{self});
    }
    fn stopThread(self: *Self) void {
        if (self.thread) |thr| {
            self.mutex.lock();
            self.quit_thread = true;
            self.mutex.unlock();

            thr.join();
        }
        self.thread = null;
    }

    fn call(self: *Self) !void {
        while (true) {
            {
                self.mutex.lock();
                defer self.mutex.unlock();

                std.debug.print("Thread loop\n", .{});

                if (self.quit_thread) {
                    std.debug.print("Stopping Thread\n", .{});
                    break;
                }
            }

            // &todo: Replace hardcoded HOME folder
            // &:zig:build:info Couple filename with build.zig.zon#name
            const config_fp = if (builtin.os.tag == .macos) "/Users/geertf/.config/champ/config.zon" else "/home/geertf/.config/champ/config.zon";
            try self.config_loader.loadFromFile(config_fp);

            const config = self.config_loader.config orelse return Error.CouldNotLoadConfig;

            const forest = self.pong();
            forest.reinit();
            try forest.load(&config, self.options);

            self.mutex.lock();
            std.debug.print("Swapping forests\n", .{});
            self.swap();
            self.mutex.unlock();
        }
    }
};
