const std = @import("std");

// Data Transfer Objects for LSP
// https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#responseMessage

pub const Request = struct {
    pub const Params = struct {
        capabilities: ?ClientCapabilities = null,
        clientInfo: ?ClientInfo = null,
        processId: ?usize = null,
        rootPath: ?[]const u8 = null,
        rootUri: ?[]const u8 = null,
        workspaceFolders: ?[]WorkspaceFolder = null,
        textDocument: ?TextDocumentItem = null,
    };

    jsonrpc: []const u8,
    method: []const u8,
    params: ?Params = null,
    id: ?i32 = null,
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
    name: []const u8 = &.{},
    kind: u32 = 7,
    range: Range = .{},
    selectionRange: Range = .{},
};

pub const TextDocumentItem = struct {
    uri: []const u8,
    languageId: ?[]const u8 = null,
    version: ?i32 = null,
    text: ?[]const u8 = null,
};

pub const WorkspaceFolder = struct {
    name: []const u8,
    uri: []const u8,
};

pub const ClientInfo = struct {
    name: []const u8,
    version: []const u8,
};

pub const ClientCapabilities = struct {
    pub const General = struct {
        positionEncodings: [][]const u8,
    };
    pub const TextDocument = struct {
        pub const ResolveSupport = struct {
            properties: [][]const u8,
        };
        pub const TagSupport = struct {
            valueSet: []i64,
        };
        pub const CodeAction = struct {
            pub const CodeActionLiteralSupport = struct {
                pub const CodeActionKind = struct {
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
        pub const Completion = struct {
            pub const CompletionItem = struct {
                deprecatedSupport: bool,
                insertReplaceSupport: bool,
                resolveSupport: ResolveSupport,
                snippetSupport: bool,
                tagSupport: TagSupport,
            };
            pub const CompletionItemKind = struct {
                // valueSet: [][]const u8 = &.{},
            };
            completionItem: CompletionItem,
            completionItemKind: CompletionItemKind,
        };
        pub const Formatting = struct {
            dynamicRegistration: bool,
        };
        pub const Hover = struct {
            contentFormat: [][]const u8,
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

pub const ServerCapabilities = struct {
    documentSymbolProvider: ?bool = null,
    workspaceSymbolProvider: ?bool = null,
};

pub const ServerInfo = struct {
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
};
