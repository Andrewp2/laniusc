pub(crate) const LANIUS_LANGUAGE_EDITION: &str = "unstable-alpha";
pub(crate) const LANIUS_EDITION_POLICY: &str =
    "no stable production language edition yet; accepts the current alpha slice only";
pub(crate) const LANIUS_DEFAULT_EMIT_TARGET: &str = "x86_64";
pub(crate) const LANIUS_EMIT_TARGETS: &str = "x86_64, wasm";
pub(crate) const LANIUS_TARGET_TRIPLES: &str = "x86_64-unknown-linux-gnu, wasm32-unknown-unknown";
pub(crate) const LANIUS_DIAGNOSTIC_FORMATS: &str = "text, json, lsp-json";
pub(crate) const LANIUS_X86_64_SUPPORT: &str = "bounded GPU HIR main-return, same-module resolver-backed scalar-const, and direct scalar helper-call source-pack slices; unsupported source shapes are rejected through GPU status";
pub(crate) const LANIUS_RELEASE_CHANNEL: &str = "source-worktree";
pub(crate) const LANIUS_DISTRIBUTION_STATUS: &str =
    "not-production-release; no stable install artifact or package manager channel";
pub(crate) const LANIUS_DOCTOR_SCHEMA_VERSION: u32 = 12;
pub(crate) const LANIUS_DIAGNOSTIC_CODES_SCHEMA_VERSION: u32 = 2;
pub(crate) const LANIUS_DIAGNOSTIC_CATEGORIES_SCHEMA_VERSION: u32 = 4;
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_NAME: &str =
    "laniusc.diagnostics.runtime-api";
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_NAME: &str =
    "laniusc.diagnostics.runtime-apis";
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_NAME: &str =
    "laniusc.diagnostics.runtime-service";
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_NAME: &str =
    "laniusc.diagnostics.runtime-service-apis";
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_NAME: &str =
    "laniusc.diagnostics.runtime-services";
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_VERSION: u32 = 2;
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_VERSION: u32 = 1;
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_VERSION: u32 = 1;
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_VERSION: u32 = 1;
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_VERSION: u32 = 1;
pub(crate) const LANIUS_SOURCE_PACK_PROGRESS_SCHEMA_VERSION: u32 = 1;
pub(crate) const LSP_STDIO_METHODS: &[&str] = &[
    "initialize",
    "initialized",
    "textDocument/didOpen",
    "textDocument/didChange",
    "textDocument/didClose",
    "textDocument/formatting",
    "textDocument/diagnostic",
    "shutdown",
    "exit",
];
pub(crate) const LSP_PRE_INITIALIZE_METHODS: &[&str] = &["initialize", "exit"];
pub(crate) const LSP_POST_SHUTDOWN_METHODS: &[&str] = &["exit"];
pub(crate) const LANIUS_LSP_CAPABILITIES_SCHEMA_NAME: &str = "laniusc.lsp.capabilities";
pub(crate) const LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION: u32 = 15;
pub(crate) const LANIUS_LSP_EXPERIMENTAL_SCHEMA_NAME: &str = "laniusc.lsp.experimental";
pub(crate) const LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION: u32 = 13;
pub(crate) const LANIUS_LSP_ERROR_DATA_SCHEMA_NAME: &str = "laniusc.lsp.error-data";
pub(crate) const LANIUS_LSP_ERROR_DATA_SCHEMA_VERSION: u32 = 2;
pub(crate) const LANIUS_LSP_PARSE_ERROR_CODE: i32 = -32700;
pub(crate) const LANIUS_LSP_INVALID_REQUEST_ERROR_CODE: i32 = -32600;
pub(crate) const LANIUS_LSP_METHOD_NOT_FOUND_ERROR_CODE: i32 = -32601;
pub(crate) const LANIUS_LSP_INVALID_PARAMS_ERROR_CODE: i32 = -32602;
pub(crate) const LANIUS_LSP_INTERNAL_ERROR_CODE: i32 = -32603;
pub(crate) const LANIUS_LSP_SERVER_NOT_INITIALIZED_ERROR_CODE: i32 = -32002;
pub(crate) const LANIUS_FORMATTER_CONTRACT: &str = "unstable-alpha lexical full-document formatter";
pub(crate) const LANIUS_FORMATTER_POLICY_SCHEMA_NAME: &str = "laniusc.formatter.policy";
pub(crate) const LANIUS_FORMATTER_POLICY_SCHEMA_VERSION: u32 = 1;
