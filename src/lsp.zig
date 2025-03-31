const std = @import("std");

const strange = @import("rubr").strange;

pub const Error = error{
    UnexpectedKey,
    CouldNotReadEOH,
    CouldNotReadContentLength,
    CouldNotReadData,
};

pub const Server = struct {
    const Self = @This();
    const Buffer = std.ArrayList(u8);

    in: std.fs.File.Reader,
    out: std.fs.File.Writer,
    log: std.fs.File.Writer,

    buffer: Buffer,

    content_length: ?usize = null,

    pub fn init(in: std.fs.File.Reader, out: std.fs.File.Writer, log: std.fs.File.Writer, ma: std.mem.Allocator) Self {
        return Self{ .in = in, .out = out, .log = log, .buffer = Buffer.init(ma) };
    }
    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    pub fn waitForRequest(self: *Self) !void {
        try self.readHeader();
        try self.readContent();
    }

    fn readHeader(self: *Self) !void {
        self.content_length = null;

        try self.buffer.resize(1024);
        if (try self.in.readUntilDelimiterOrEof(self.buffer.items, '\r')) |line| {
            try self.log.print("[Line](content:{s})\n", .{line});

            var str = strange.Strange.init(line);

            if (str.popTo(':')) |key| {
                if (!std.mem.eql(u8, key, "Content-Length"))
                    return Error.UnexpectedKey;
            }
            _ = str.popMany(' ');

            self.content_length = if (str.popInt(usize)) |i| i else return Error.CouldNotReadContentLength;
            try self.buffer.resize(3);
            if (try self.in.readAll(self.buffer.items) != 3) return Error.CouldNotReadEOH;
            if (!std.mem.eql(u8, self.buffer.items, "\n\r\n")) return Error.CouldNotReadEOH;
        }
    }

    fn readContent(self: *Self) !void {
        if (self.content_length) |cl| {
            try self.buffer.resize(cl);
            if (try self.in.readAll(self.buffer.items) != cl) return Error.CouldNotReadData;
            try self.log.print("data:{s}\n", .{self.buffer.items});
        }
    }
};

test "lsp" {
    const ut = std.testing;

    const request =
        \\{
        \\  "jsonrpc": "2.0",
        \\  "method": "initialize",
        \\  "params": {
        \\    "capabilities": {
        \\      "general": {
        \\        "positionEncodings": [
        \\          "utf-8",
        \\          "utf-32",
        \\          "utf-16"
        \\        ]
        \\      },
        \\      "textDocument": {
        \\        "codeAction": {
        \\          "codeActionLiteralSupport": {
        \\            "codeActionKind": {
        \\              "valueSet": [
        \\                "",
        \\                "quickfix",
        \\                "refactor",
        \\                "refactor.extract",
        \\                "refactor.inline",
        \\                "refactor.rewrite",
        \\                "source",
        \\                "source.organizeImports"
        \\              ]
        \\            }
        \\          },
        \\          "dataSupport": true,
        \\          "disabledSupport": true,
        \\          "isPreferredSupport": true,
        \\          "resolveSupport": {
        \\            "properties": [
        \\              "edit",
        \\              "command"
        \\            ]
        \\          }
        \\        },
        \\        "completion": {
        \\          "completionItem": {
        \\            "deprecatedSupport": true,
        \\            "insertReplaceSupport": true,
        \\            "resolveSupport": {
        \\              "properties": [
        \\                "documentation",
        \\                "detail",
        \\                "additionalTextEdits"
        \\              ]
        \\            },
        \\            "snippetSupport": true,
        \\            "tagSupport": {
        \\              "valueSet": [
        \\                1
        \\              ]
        \\            }
        \\          },
        \\          "completionItemKind": {}
        \\        },
        \\        "formatting": {
        \\          "dynamicRegistration": false
        \\        },
        \\        "hover": {
        \\          "contentFormat": [
        \\            "markdown"
        \\          ]
        \\        },
        \\        "inlayHint": {
        \\          "dynamicRegistration": false
        \\        },
        \\        "publishDiagnostics": {
        \\          "tagSupport": {
        \\            "valueSet": [
        \\              1,
        \\              2
        \\            ]
        \\          },
        \\          "versionSupport": true
        \\        },
        \\        "rename": {
        \\          "dynamicRegistration": false,
        \\          "honorsChangeAnnotations": false,
        \\          "prepareSupport": true
        \\        },
        \\        "signatureHelp": {
        \\          "signatureInformation": {
        \\            "activeParameterSupport": true,
        \\            "documentationFormat": [
        \\              "markdown"
        \\            ],
        \\            "parameterInformation": {
        \\              "labelOffsetSupport": true
        \\            }
        \\          }
        \\        }
        \\      },
        \\      "window": {
        \\        "workDoneProgress": true
        \\      },
        \\      "workspace": {
        \\        "applyEdit": true,
        \\        "configuration": true,
        \\        "didChangeConfiguration": {
        \\          "dynamicRegistration": false
        \\        },
        \\        "didChangeWatchedFiles": {
        \\          "dynamicRegistration": true,
        \\          "relativePatternSupport": false
        \\        },
        \\        "executeCommand": {
        \\          "dynamicRegistration": false
        \\        },
        \\        "fileOperations": {
        \\          "didRename": true,
        \\          "willRename": true
        \\        },
        \\        "inlayHint": {
        \\          "refreshSupport": false
        \\        },
        \\        "symbol": {
        \\          "dynamicRegistration": false
        \\        },
        \\        "workspaceEdit": {
        \\          "documentChanges": true,
        \\          "failureHandling": "abort",
        \\          "normalizesLineEndings": false,
        \\          "resourceOperations": [
        \\            "create",
        \\            "rename",
        \\            "delete"
        \\          ]
        \\        },
        \\        "workspaceFolders": true
        \\      }
        \\    },
        \\    "clientInfo": {
        \\      "name": "helix",
        \\      "version": "25.1 (911ecbb6)"
        \\    },
        \\    "processId": 547208,
        \\    "rootPath": "/home/geertf/chimp",
        \\    "rootUri": "file:///home/geertf/chimp",
        \\    "workspaceFolders": [
        \\      {
        \\        "name": "chimp",
        \\        "uri": "file:///home/geertf/chimp"
        \\      }
        \\    ]
        \\  },
        \\  "id": 0
        \\}
    ;
    const Request = struct {
        const Params = struct {
            const Capabilities = struct {
                const General = struct {
                    positionEncodings: [][]const u8,
                };
                const TextDocument = struct {
                    const ResolveSupport = struct {
                        properties: [][]const u8,
                    };
                    const TagSupport = struct {
                        valueSet: []i64,
                    };
                    const CodeAction = struct {
                        const CodeActionLiteralSupport = struct {
                            const CodeActionKind = struct {
                                valueSet: [][]const u8,
                            };
                            codeActionKind: CodeActionKind,
                        };
                        codeActionLiteralSupport: CodeActionLiteralSupport,
                        dataSupport: bool,
                        disabledSupport: bool,
                        isPreferredSupport: bool,
                        resolveSupport: ResolveSupport,
                    };
                    const Completion = struct {
                        const CompletionItem = struct {
                            deprecatedSupport: bool,
                            insertReplaceSupport: bool,
                            resolveSupport: ResolveSupport,
                            snippetSupport: bool,
                            tagSupport: TagSupport,
                        };
                        const CompletionItemKind = struct {
                            // valueSet: [][]const u8 = &.{},
                        };
                        completionItem: CompletionItem,
                        completionItemKind: CompletionItemKind,
                    };
                    const Formatting = struct {
                        dynamicRegistration: bool,
                    };
                    const Hover = struct {
                        contentFormat: [][]const u8,
                    };
                    const InlayHint = struct {
                        dynamicRegistration: bool,
                    };
                    const PublishDiagnostics = struct {
                        tagSupport: TagSupport,
                        versionSupport: bool,
                    };
                    const Rename = struct {
                        dynamicRegistration: bool,
                        honorsChangeAnnotations: bool,
                        prepareSupport: bool,
                    };
                    const SignatureHelp = struct {
                        const SignatureInformation = struct {
                            const ParameterInformation = struct {
                                labelOffsetSupport: bool,
                            };
                            activeParameterSupport: bool,
                            documentationFormat: [][]const u8,
                            parameterInformation: ParameterInformation,
                        };
                        signatureInformation: SignatureInformation,
                    };

                    codeAction: CodeAction,
                    completion: Completion,
                    formatting: Formatting,
                    hover: Hover,
                    inlayHint: InlayHint,
                    publishDiagnostics: PublishDiagnostics,
                    rename: Rename,
                    signatureHelp: SignatureHelp,
                };
                const Window = struct {
                    workDoneProgress: bool,
                };

                general: General,
                textDocument: TextDocument,
                window: Window,
                workspace: Workspace,
                const Workspace = struct {
                    const DidChangeConfiguration = struct {
                        dynamicRegistration: bool,
                    };
                    const DidChangeWatchedFiles = struct {
                        dynamicRegistration: bool,
                        relativePatternSupport: bool,
                    };
                    const ExecuteCommand = struct {
                        dynamicRegistration: bool,
                    };
                    const FileOperations = struct {
                        didRename: bool,
                        willRename: bool,
                    };
                    const InlayHint = struct {
                        refreshSupport: bool,
                    };
                    const Symbol = struct {
                        dynamicRegistration: bool,
                    };
                    const WorkspaceEdit = struct {
                        documentChanges: bool,
                        failureHandling: []const u8,
                        normalizesLineEndings: bool,
                        resourceOperations: [][]const u8,
                    };

                    applyEdit: bool,
                    configuration: bool,
                    didChangeConfiguration: DidChangeConfiguration,
                    didChangeWatchedFiles: DidChangeWatchedFiles,
                    executeCommand: ExecuteCommand,
                    fileOperations: FileOperations,
                    inlayHint: InlayHint,
                    symbol: Symbol,
                    workspaceEdit: WorkspaceEdit,
                    workspaceFolders: bool,
                };
            };
            const ClientInfo = struct {
                name: []const u8,
                version: []const u8,
            };
            const WorkspaceFolder = struct {
                name: []const u8,
                uri: []const u8,
            };

            capabilities: Capabilities,
            clientInfo: ClientInfo,
            processId: usize,
            rootPath: []const u8,
            rootUri: []const u8,
            workspaceFolders: []WorkspaceFolder,
        };

        jsonrpc: []const u8,
        method: []const u8,
        params: Params,
        id: usize,
    };
    var aa = std.heap.ArenaAllocator.init(ut.allocator);
    defer aa.deinit();
    const p = try std.json.parseFromSlice(Request, aa.allocator(), request, .{});
    std.debug.print("p: {}\n", .{p.value});
}
