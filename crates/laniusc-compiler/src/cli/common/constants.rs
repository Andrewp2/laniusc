/// Current accepted language edition string for CLI validation.
pub(crate) const LANIUS_LANGUAGE_EDITION: &str = "unstable-alpha";
/// Human-readable policy shown when an unsupported edition is requested.
pub(crate) const LANIUS_EDITION_POLICY: &str =
    "no stable production language edition yet; accepts the current alpha slice only";
/// Default target emitted when `--emit` is omitted.
pub(crate) const LANIUS_DEFAULT_EMIT_TARGET: &str = "x86_64";
/// Accepted `--emit` values.
pub(crate) const LANIUS_EMIT_TARGETS: &str = "x86_64, wasm";
/// Accepted `--target` triples and their implied emit targets.
pub(crate) const LANIUS_TARGET_TRIPLES: &str = "x86_64-unknown-linux-gnu, wasm32-unknown-unknown";
/// Accepted diagnostic rendering formats.
pub(crate) const LANIUS_DIAGNOSTIC_FORMATS: &str = "text, json, lsp-json";
/// Current x86_64 feature-slice description printed in help and version output.
pub(crate) const LANIUS_X86_64_SUPPORT: &str = "bounded HIR main-return, same-module resolver-backed scalar constants, and direct scalar helper-call source-pack slices; unsupported source shapes are reported as unsupported-feature diagnostics";
/// Release channel label reported by version and policy metadata commands.
pub(crate) const LANIUS_RELEASE_CHANNEL: &str = "source-worktree";
/// Distribution status label reported by version and policy metadata commands.
pub(crate) const LANIUS_DISTRIBUTION_STATUS: &str =
    "not-production-release; no stable install artifact or package manager channel";
/// Schema version for `laniusc doctor` JSON.
pub(crate) const LANIUS_DOCTOR_SCHEMA_VERSION: u32 = 12;
/// Schema version for compact diagnostic-code JSON.
pub(crate) const LANIUS_DIAGNOSTIC_CODES_SCHEMA_VERSION: u32 = 2;
/// Schema version for diagnostic-category JSON.
pub(crate) const LANIUS_DIAGNOSTIC_CATEGORIES_SCHEMA_VERSION: u32 = 4;
/// Schema name for one runtime-bound API metadata response.
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_NAME: &str =
    "laniusc.diagnostics.runtime-api";
/// Schema name for all runtime-bound API metadata.
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_NAME: &str =
    "laniusc.diagnostics.runtime-apis";
/// Schema name for one runtime service boundary metadata response.
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_NAME: &str =
    "laniusc.diagnostics.runtime-service";
/// Schema name for APIs owned by one runtime service.
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_NAME: &str =
    "laniusc.diagnostics.runtime-service-apis";
/// Schema name for all runtime service boundary metadata.
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_NAME: &str =
    "laniusc.diagnostics.runtime-services";
/// Schema version for one runtime-bound API metadata response.
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_VERSION: u32 = 2;
/// Schema version for all runtime-bound API metadata.
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_VERSION: u32 = 1;
/// Schema version for one runtime service boundary metadata response.
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_VERSION: u32 = 1;
/// Schema version for APIs owned by one runtime service.
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_VERSION: u32 = 1;
/// Schema version for all runtime service boundary metadata.
pub(crate) const LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_VERSION: u32 = 1;
/// Schema version for source-pack progress metadata.
pub(crate) const LANIUS_SOURCE_PACK_PROGRESS_SCHEMA_VERSION: u32 = 1;
/// LSP methods supported by the stdio server.
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
/// LSP methods accepted before initialization.
pub(crate) const LSP_PRE_INITIALIZE_METHODS: &[&str] = &["initialize", "exit"];
/// LSP methods accepted after shutdown.
pub(crate) const LSP_POST_SHUTDOWN_METHODS: &[&str] = &["exit"];
/// Schema name for LSP capability JSON.
pub(crate) const LANIUS_LSP_CAPABILITIES_SCHEMA_NAME: &str = "laniusc.lsp.capabilities";
/// Schema version for LSP capability JSON.
pub(crate) const LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION: u32 = 15;
/// Schema name for LSP experimental metadata.
pub(crate) const LANIUS_LSP_EXPERIMENTAL_SCHEMA_NAME: &str = "laniusc.lsp.experimental";
/// Schema version for LSP experimental metadata.
pub(crate) const LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION: u32 = 13;
/// Schema name for LSP error-data metadata.
pub(crate) const LANIUS_LSP_ERROR_DATA_SCHEMA_NAME: &str = "laniusc.lsp.error-data";
/// Schema version for LSP error-data metadata.
pub(crate) const LANIUS_LSP_ERROR_DATA_SCHEMA_VERSION: u32 = 2;
/// JSON-RPC parse-error code used by the LSP server.
pub(crate) const LANIUS_LSP_PARSE_ERROR_CODE: i32 = -32700;
/// JSON-RPC invalid-request code used by the LSP server.
pub(crate) const LANIUS_LSP_INVALID_REQUEST_ERROR_CODE: i32 = -32600;
/// JSON-RPC method-not-found code used by the LSP server.
pub(crate) const LANIUS_LSP_METHOD_NOT_FOUND_ERROR_CODE: i32 = -32601;
/// JSON-RPC invalid-params code used by the LSP server.
pub(crate) const LANIUS_LSP_INVALID_PARAMS_ERROR_CODE: i32 = -32602;
/// JSON-RPC internal-error code used by the LSP server.
pub(crate) const LANIUS_LSP_INTERNAL_ERROR_CODE: i32 = -32603;
/// LSP server-not-initialized error code.
pub(crate) const LANIUS_LSP_SERVER_NOT_INITIALIZED_ERROR_CODE: i32 = -32002;
/// Formatter contract string reported to CLI and LSP metadata consumers.
pub(crate) const LANIUS_FORMATTER_CONTRACT: &str = "unstable-alpha lexical full-document formatter";
/// Schema name for formatter policy metadata.
pub(crate) const LANIUS_FORMATTER_POLICY_SCHEMA_NAME: &str = "laniusc.formatter.policy";
/// Schema version for formatter policy metadata.
pub(crate) const LANIUS_FORMATTER_POLICY_SCHEMA_VERSION: u32 = 1;
