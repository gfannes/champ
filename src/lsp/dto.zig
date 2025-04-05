const std = @import("std");

// Data Transfer Objects for LSP
// https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#responseMessage

pub const String = []const u8;

pub const Request = struct {
    pub const Params = struct {
        capabilities: ?ClientCapabilities = null,
        clientInfo: ?ClientInfo = null,
        processId: ?usize = null,
        rootPath: ?String = null,
        rootUri: ?String = null,
        workspaceFolders: ?[]WorkspaceFolder = null,
        textDocument: ?TextDocumentItem = null,
        query: ?String = null,
    };

    jsonrpc: String,
    method: String,
    params: ?Params = null,
    id: ?i32 = null,

    pub fn is(self: Request, method: String) bool {
        return std.mem.eql(u8, method, self.method);
    }
};

// Generic Response with injected, optional Result
// &todo: Add support for 'error'
pub fn Response(Result: type) type {
    return struct {
        id: i32,
        result: ?*const Result,
    };
}

pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
    serverInfo: ServerInfo,
};

pub const Position = struct {
    line: u32 = 0,
    character: u32 = 0,
};

pub const Range = struct {
    start: Position = .{},
    end: Position = .{},
};

pub const DocumentSymbol = struct {
    name: String = &.{},
    kind: u32 = 7,
    range: Range = .{},
    selectionRange: Range = .{},
};

pub const WorkspaceSymbol = struct {
    name: String = &.{},
    kind: u32 = 7,
    location: Location = .{},
    containerName: ?String = null,
    score: ?f32 = null,
};

pub const Location = struct {
    uri: String = &.{},
    range: Range = .{},
};

pub const TextDocumentItem = struct {
    uri: String,
    languageId: ?String = null,
    version: ?i32 = null,
    text: ?String = null,
};

pub const WorkspaceFolder = struct {
    name: String,
    uri: String,
};

pub const ClientInfo = struct {
    name: String,
    version: String,
};

pub const ClientCapabilities = struct {
    pub const General = struct {
        positionEncodings: []String,
    };
    pub const TextDocument = struct {
        pub const ResolveSupport = struct {
            properties: []String,
        };
        pub const TagSupport = struct {
            valueSet: []i64,
        };
        pub const CodeAction = struct {
            pub const CodeActionLiteralSupport = struct {
                pub const CodeActionKind = struct {
                    valueSet: []String,
                };
                codeActionKind: CodeActionKind,
            };
            codeActionLiteralSupport: CodeActionLiteralSupport,
            dataSupport: bool,
            disabledSupport: bool,
            isPreferredSupport: bool,
            resolveSupport: ResolveSupport,
        };
        pub const Completion = struct {
            pub const CompletionItem = struct {
                deprecatedSupport: bool,
                insertReplaceSupport: bool,
                resolveSupport: ResolveSupport,
                snippetSupport: bool,
                tagSupport: TagSupport,
            };
            pub const CompletionItemKind = struct {
                // valueSet: []String = &.{},
            };
            completionItem: CompletionItem,
            completionItemKind: CompletionItemKind,
        };
        pub const Formatting = struct {
            dynamicRegistration: bool,
        };
        pub const Hover = struct {
            contentFormat: []String,
        };
        pub const InlayHint = struct {
            dynamicRegistration: bool,
        };
        pub const PublishDiagnostics = struct {
            tagSupport: TagSupport,
            versionSupport: bool,
        };
        pub const Rename = struct {
            dynamicRegistration: bool,
            honorsChangeAnnotations: bool,
            prepareSupport: bool,
        };
        pub const SignatureHelp = struct {
            pub const SignatureInformation = struct {
                pub const ParameterInformation = struct {
                    labelOffsetSupport: bool,
                };
                activeParameterSupport: bool,
                documentationFormat: []String,
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
    pub const Window = struct {
        workDoneProgress: bool,
    };

    general: General,
    textDocument: TextDocument,
    window: Window,
    workspace: Workspace,
    pub const Workspace = struct {
        pub const DidChangeConfiguration = struct {
            dynamicRegistration: bool,
        };
        pub const DidChangeWatchedFiles = struct {
            dynamicRegistration: bool,
            relativePatternSupport: bool,
        };
        pub const ExecuteCommand = struct {
            dynamicRegistration: bool,
        };
        pub const FileOperations = struct {
            didRename: bool,
            willRename: bool,
        };
        pub const InlayHint = struct {
            refreshSupport: bool,
        };
        pub const Symbol = struct {
            dynamicRegistration: bool,
        };
        pub const WorkspaceEdit = struct {
            documentChanges: bool,
            failureHandling: String,
            normalizesLineEndings: bool,
            resourceOperations: []String,
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

pub const ServerCapabilities = struct {
    pub const Workspace = struct {
        pub const WorkspaceFolders = struct {
            supported: bool,
        };

        workspaceFolders: ?WorkspaceFolders = null,
    };

    documentSymbolProvider: ?bool = null,
    workspaceSymbolProvider: ?bool = null,
    workspace: ?Workspace = null,
};

pub const ServerInfo = struct {
    name: ?String = null,
    version: ?String = null,
};
