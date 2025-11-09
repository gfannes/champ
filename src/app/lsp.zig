const std = @import("std");
const builtin = @import("builtin");

const rubr = @import("rubr");
const lsp = rubr.lsp;
const strings = rubr.strings;
const fuzz = rubr.fuzz;
const Env = rubr.Env;

const cfg = @import("../cfg.zig");
const mero = @import("../mero.zig");
const amp = @import("../amp.zig");
const qry = @import("../qry.zig");

pub const Error = error{
    ExpectedParams,
    ExpectedQuery,
    ExpectedTextDocument,
    ExpectedContext,
    UnexpectedFilenameFormat,
    ExpectedPosition,
    CouldNotLoadConfig,
    ThreadNotRunning,
};

pub const Lsp = struct {
    const Self = @This();

    env: Env,
    config: *const cfg.file.Config,
    cli_args: *const cfg.cli.Args,

    forest_pp: ForestPP = undefined,

    pub fn init(self: *Self) !void {
        self.forest_pp = .{ .env = self.env, .cli_args = self.cli_args };
        self.forest_pp.init();
    }
    pub fn deinit(self: *Self) void {
        self.forest_pp.deinit();
    }

    pub fn call(self: *Self) !void {
        try self.env.log.info("Lsp server started {}\n", .{(try std.time.Instant.now()).timestamp});

        var readbuf: [1024]u8 = undefined;
        var cin = std.fs.File.stdin().reader(self.env.io, &readbuf);

        var writebuf: [1024]u8 = undefined;
        var cout = std.fs.File.stdout().writer(&writebuf);

        var server = lsp.Server.init(&cin.interface, &cout.interface, self.env.log.writer(), self.env.a);
        defer server.deinit();

        try self.forest_pp.startThread();

        var count: usize = 0;
        var do_continue = true;
        var init_ok = false;
        while (do_continue) : (count += 1) {
            try self.env.log.info("[Iteration](count:{})\n", .{count});

            const request = try server.receive();

            const forest, const mutex = try self.forest_pp.waitForPing();
            defer mutex.unlock();

            const dto = lsp.dto;
            if (request.id) |_| {
                if (request.is("initialize")) {
                    const triggerCharacters = [_][]const u8{"&"};
                    const result = dto.InitializeResult{
                        .capabilities = dto.ServerCapabilities{
                            .textDocumentSync = dto.ServerCapabilities.TextDocumentSyncOptions{},
                            .completionProvider = dto.ServerCapabilities.CompletionOptions{ .triggerCharacters = &triggerCharacters },
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

                    const params = request.params orelse return Error.ExpectedParams;
                    const textdoc = params.textDocument orelse return Error.ExpectedTextDocument;
                    const position = params.position orelse return Error.ExpectedPosition;

                    var aa = std.heap.ArenaAllocator.init(self.env.a);
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
                            if (def.ap.isFit(e)) {
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
                    const params = request.params orelse return Error.ExpectedParams;
                    const textdoc = params.textDocument orelse return Error.ExpectedTextDocument;
                    const position = params.position orelse return Error.ExpectedPosition;

                    var aa = std.heap.ArenaAllocator.init(self.env.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();

                    var src_filename_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const src_filename = try uriToPath_(textdoc.uri, &src_filename_buf, aaa);

                    // Find Amp
                    var maybe_ap: ?amp.Path = null;
                    for (forest.chores.list.items) |chore| {
                        if (!std.mem.endsWith(u8, src_filename, chore.path))
                            continue;

                        // We only check the org parts for references, not all inherited agg parts
                        for (chore.parts.items[0..chore.org_count]) |part| {
                            if (part.row == position.line and (part.cols.begin <= position.character and position.character <= part.cols.end)) {
                                if (maybe_ap) |ap|
                                    std.debug.print("Already found an amp: '{f}' in '{s}' for path '{s}' part count {}\n", .{ ap, src_filename, chore.path, chore.parts.items.len });
                                maybe_ap = part.ap;
                            }
                        }
                    }

                    // Find all usage locations
                    if (maybe_ap) |ap| {
                        var locations = std.ArrayList(dto.Location){};
                        for (forest.chores.list.items) |chore| {
                            for (chore.parts.items[0..chore.org_count]) |part| {
                                if (ap.isFit(part.ap)) {
                                    const uri = try pathToUri_(chore.path, aaa);
                                    const range = dto.Range{
                                        .start = dto.Position{ .line = @intCast(part.row), .character = @intCast(part.cols.begin) },
                                        .end = dto.Position{ .line = @intCast(part.row), .character = @intCast(part.cols.end) },
                                    };
                                    const location = dto.Location{ .uri = uri, .range = range };
                                    try locations.append(aaa, location);
                                }
                            }
                        }
                        try server.send(locations.items);
                    } else {
                        try server.send(null);
                    }
                } else if (request.is("textDocument/documentSymbol")) {
                    const params = request.params orelse return Error.ExpectedParams;
                    const textdoc = params.textDocument orelse return Error.ExpectedTextDocument;

                    var aa = std.heap.ArenaAllocator.init(self.env.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();

                    var filename_buf: [std.fs.max_path_bytes]u8 = undefined;
                    const filename = try uriToPath_(textdoc.uri, &filename_buf, aaa);

                    var document_symbols = std.ArrayList(dto.DocumentSymbol){};

                    for (forest.chores.list.items) |chore| {
                        if (!std.mem.endsWith(u8, filename, chore.path))
                            continue;

                        if (rubr.slc.is_empty(chore.parts.items)) {
                            try self.env.log.warning("Expected to find at least one AMP for Chore\n", .{});
                            continue;
                        }

                        if (chore.isDone())
                            continue;

                        const first_amp = &chore.parts.items[0];
                        const last_amp = &chore.parts.items[chore.org_count - 1];
                        const range = dto.Range{
                            .start = dto.Position{ .line = @intCast(first_amp.row), .character = @intCast(first_amp.cols.begin) },
                            .end = dto.Position{ .line = @intCast(last_amp.row), .character = @intCast(last_amp.cols.end) },
                        };
                        try document_symbols.append(aaa, dto.DocumentSymbol{
                            .name = chore.str,
                            .range = range,
                            .selectionRange = range,
                        });
                    }

                    try server.send(document_symbols.items);
                } else if (request.is("textDocument/completion")) {
                    const params = request.params orelse return Error.ExpectedParams;
                    const context = params.context orelse return Error.ExpectedContext;

                    var aa = std.heap.ArenaAllocator.init(self.env.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();

                    var completions = std.ArrayList(dto.CompletionItem){};

                    for (forest.chores.amps.items) |item| {
                        if (rubr.slc.lastPtr(item.ap.parts.items)) |part| {
                            if (context.triggerCharacter) |_| {
                                try completions.append(aaa, dto.CompletionItem{
                                    .label = part.content,
                                    .kind = 14,
                                });
                            }
                        }
                    }

                    try server.send(completions.items);
                } else if (request.is("workspace/symbol")) {
                    const params = request.params orelse return Error.ExpectedParams;
                    const query = params.query orelse return Error.ExpectedQuery;

                    var aa = std.heap.ArenaAllocator.init(self.env.a);
                    defer aa.deinit();
                    const aaa = aa.allocator();
                    var workspace_symbols = std.ArrayList(dto.WorkspaceSymbol){};

                    var q = qry.Query.init(self.env.a);
                    defer q.deinit();
                    try q.setup(&[_][]const u8{query});

                    for (forest.chores.list.items) |chore| {
                        if (rubr.slc.is_empty(chore.parts.items)) {
                            try self.env.log.warning("Expected to find at least one AMP per Chore\n", .{});
                            continue;
                        }

                        if (q.distance(chore)) |distance| {
                            const first_amp = &chore.parts.items[0];
                            const last_amp = &chore.parts.items[chore.org_count - 1];
                            const range = dto.Range{
                                .start = dto.Position{ .line = @intCast(first_amp.row), .character = @intCast(first_amp.cols.begin) },
                                .end = dto.Position{ .line = @intCast(last_amp.row), .character = @intCast(last_amp.cols.end) },
                            };
                            try workspace_symbols.append(aaa, dto.WorkspaceSymbol{
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
                    try self.env.log.warning("Unhandled request '{s}'\n", .{request.method});
                }
            } else {
                if (request.is("textDocument/didOpen")) {
                    // Nothing todo
                } else if (request.is("textDocument/didChange")) {
                    // Force a reload, but do not wait for it
                    self.forest_pp.reload_counter = 0;
                } else if (request.is("initialized")) {
                    init_ok = true;
                } else if (request.is("exit")) {
                    do_continue = false;
                } else {
                    try self.env.log.warning("Unhandled notification '{s}'\n", .{request.method});
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

    env: Env,
    cli_args: *const cfg.cli.Args,

    config_loader: cfg.file.Loader = undefined,

    mutex: std.Thread.Mutex = .{},

    thread: ?std.Thread = null,
    quit_thread: bool = false,

    pp: [2]mero.Forest = undefined,
    ping_is_first: bool = true,

    reload_counter: usize = 0,

    pub fn init(self: *Self) void {
        self.config_loader = try cfg.file.Loader.init(self.env);
        for (&self.pp) |*forest| {
            forest.* = .{ .env = self.env };
            forest.init();
        }
    }
    pub fn deinit(self: *Self) void {
        self.stopThread();
        self.config_loader.deinit();
        for (&self.pp) |*forest|
            forest.deinit();
    }

    // Unlock the mutex when finished working with forest
    pub fn waitForPing(self: *Self) !struct { *mero.Forest, *std.Thread.Mutex } {
        while (true) {
            {
                self.mutex.lock();
                if (self.quit_thread) {
                    self.mutex.unlock();
                    return Error.ThreadNotRunning;
                }
                const forest = self.ping();
                if (forest.valid)
                    return .{ forest, &self.mutex };
                self.mutex.unlock();
            }

            try self.env.io.sleep(std.Io.Duration.fromMilliseconds(10), std.Io.Clock.real);
            // std.Thread.sleep(_10_ms);
        }
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

    fn ping(self: *Self) *mero.Forest {
        return &self.pp[if (self.ping_is_first) 0 else 1];
    }
    fn pong(self: *Self) *mero.Forest {
        return &self.pp[if (self.ping_is_first) 1 else 0];
    }

    fn call(self: *Self) !void {
        while (true) {
            var reload: bool = false;

            {
                self.mutex.lock();
                defer self.mutex.unlock();

                if (self.quit_thread) {
                    std.debug.print("Stopping Thread\n", .{});
                    return;
                }

                if (!self.ping().valid)
                    reload = true;

                if (self.reload_counter == 0) {
                    reload = true;
                    // Reload every 5min
                    self.reload_counter = 5 * 60 * 10;
                } else {
                    self.reload_counter -= 1;
                }
            }

            // &todo: Replace hardcoded HOME folder
            // &:zig:build:info Couple filename with build.zig.zon#name
            const config_fp = if (builtin.os.tag == .macos) "/Users/geertf/.config/champ/config.zon" else "/home/geertf/.config/champ/config.zon";
            if (try self.config_loader.loadFromFile(config_fp)) {
                std.debug.print("Found new config\n", .{});
                reload = true;
            }

            if (reload) {
                const config = self.config_loader.config orelse return Error.CouldNotLoadConfig;

                const forest = self.pong();
                forest.reinit();
                try forest.load(&config, self.cli_args);

                // Swap ping and pong
                {
                    self.mutex.lock();
                    defer self.mutex.unlock();
                    self.ping_is_first = !self.ping_is_first;
                }
            }

            try self.env.io.sleep(std.Io.Duration.fromMilliseconds(100), std.Io.Clock.real);
        }
    }
};
