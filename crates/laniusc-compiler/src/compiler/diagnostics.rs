use std::{
    fmt,
    path::{Path, PathBuf},
};

use serde::Serialize;

use crate::{
    lexer::{
        tables::tokens::TokenKind,
        types::{GpuToken, Token},
        util::read_tokens_from_mapped,
    },
    parser::{driver::ParserFailure, tables::Ll1RejectionContext},
};

/// Public severity class used by rendered diagnostics and diagnostic registries.
///
/// The compiler currently exposes only hard errors. Keeping severity as a
/// serializable enum rather than a string leaves the JSON and LSP metadata ready
/// for warnings or notes without changing the surrounding payload shape.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DiagnosticSeverity {
    /// A diagnostic that prevents successful compilation or command execution.
    Error,
}

impl DiagnosticSeverity {
    fn as_str(&self) -> &'static str {
        match self {
            DiagnosticSeverity::Error => "error",
        }
    }
}

/// Stable registry row for one public diagnostic code.
///
/// The registry is consumed by CLI metadata commands, JSON renderers, and LSP
/// capability payloads. Fields here describe the public diagnostic contract,
/// not an implementation site that may move inside the compiler.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct DiagnosticCodeInfo {
    /// Stable `LNC####` code shown to users and tools.
    pub code: &'static str,
    /// Short title associated with the code.
    pub title: &'static str,
    /// Stable category used for filtering and grouped metadata output.
    pub category: &'static str,
    /// Whether normal instances of this code should carry a primary source label.
    pub primary_label_policy: DiagnosticPrimaryLabelPolicy,
    /// Default severity used by text and JSON renderers.
    pub default_severity: DiagnosticSeverity,
    /// LSP `Diagnostic.source` value for this code.
    pub lsp_source: &'static str,
    /// Numeric LSP `DiagnosticSeverity` value for this code.
    pub lsp_severity: u8,
}

/// Registry policy for whether a code is expected to identify source text.
///
/// This is advisory metadata for tools. Runtime construction still allows a
/// diagnostic to omit a label when the failure happens before a source location
/// is available.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum DiagnosticPrimaryLabelPolicy {
    /// Diagnostics for this code should normally include a primary label.
    Required,
    /// Diagnostics for this code are not expected to include a source label.
    None,
}

/// LSP diagnostic source string used by compiler-produced diagnostics.
pub const LSP_DIAGNOSTIC_SOURCE: &str = "laniusc";
/// Numeric LSP `DiagnosticSeverity.Error` value used for compiler errors.
pub const LSP_DIAGNOSTIC_ERROR_SEVERITY: u8 = 1;
/// Position encoding used by the LSP-facing diagnostic range fields.
pub const LSP_POSITION_ENCODING: &str = "utf-16";
/// Schema name for the compiler's rendered diagnostic JSON payload.
pub const DIAGNOSTIC_JSON_SCHEMA_NAME: &str = "laniusc.diagnostics.rendered-json";
/// Schema name embedded in the `data` field of LSP-shaped diagnostics.
pub const LSP_DIAGNOSTIC_DATA_SCHEMA_NAME: &str = "laniusc.diagnostics.lsp-data";
/// Version of the rendered diagnostic JSON payload.
pub const DIAGNOSTIC_JSON_SCHEMA_VERSION: u32 = 4;
/// Version of the LSP diagnostic `data` payload.
pub const LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION: u32 = 5;

impl DiagnosticCodeInfo {
    const fn error(
        code: &'static str,
        title: &'static str,
        category: &'static str,
        primary_label_policy: DiagnosticPrimaryLabelPolicy,
    ) -> Self {
        Self {
            code,
            title,
            category,
            primary_label_policy,
            default_severity: DiagnosticSeverity::Error,
            lsp_source: LSP_DIAGNOSTIC_SOURCE,
            lsp_severity: LSP_DIAGNOSTIC_ERROR_SEVERITY,
        }
    }
}

/// Ordered registry of every stable diagnostic code emitted by the compiler.
///
/// Codes are sorted and unique so wrappers can binary-search, diff versions, or
/// present stable completion lists without compiling source. Adding a new
/// diagnostic code is a public metadata change and should update the registry
/// tests and explanation metadata together.
pub const DIAGNOSTIC_CODE_REGISTRY: &[DiagnosticCodeInfo] = &[
    DiagnosticCodeInfo::error(
        "LNC0001",
        "missing source-root module",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0002",
        "import cycle",
        "module resolution",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0003",
        "ambiguous source-root module",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0004",
        "source-root escape",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0005",
        "unresolved identifier",
        "name resolution",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0006",
        "type mismatch",
        "type checking",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0007",
        "unknown type",
        "type checking",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0008",
        "unsatisfied trait bound",
        "trait solving",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0009",
        "ambiguous trait bound",
        "trait solving",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0010",
        "unresolved import",
        "module resolution",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0011",
        "unsupported import form",
        "module resolution",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0012",
        "import path too deep",
        "module resolution",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0013",
        "duplicate module declaration",
        "module resolution",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0014",
        "module path too deep",
        "module resolution",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0015",
        "invalid module path",
        "module resolution",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0016",
        "syntax error",
        "parsing",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0017",
        "x86 backend boundary",
        "native codegen",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0018",
        "unsupported CLI option value",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0019",
        "formatter check failed",
        "tooling",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0020",
        "unknown CLI option",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0021",
        "invalid trait implementation",
        "trait solving",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0022",
        "linked-output contract descriptor",
        "native codegen",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0023",
        "missing CLI option value",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0024",
        "source-root package boundary",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0025",
        "missing CLI subcommand",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0026",
        "missing CLI argument",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0027",
        "call resolution failed",
        "type checking",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0028",
        "unsupported LSP method",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0029",
        "invalid LSP message",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0030",
        "non-source source-root module",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0031",
        "unexpected CLI argument",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0032",
        "incompatible CLI options",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0033",
        "invalid generic parameter list",
        "type checking",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0034",
        "output write failed",
        "tooling",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0035",
        "output stream write failed",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0036",
        "WASM backend boundary",
        "target codegen",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0037",
        "package metadata invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0038",
        "runtime service boundary",
        "runtime binding",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0039",
        "unknown CLI subcommand",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0040",
        "input read failed",
        "tooling",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0041",
        "invalid loop control",
        "type checking",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0042",
        "invalid member access",
        "type checking",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0043",
        "invalid array return",
        "type checking",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0044",
        "compiler limit exceeded",
        "type checking",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0045",
        "unclassified type-check rejection",
        "type checking",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0046",
        "source tokenization failed",
        "parsing",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0047",
        "type-check execution failed",
        "type checking",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0048",
        "source-pack input limit exceeded",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0049",
        "explicit source-pack manifest invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0050",
        "source-pack library partition invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0051",
        "source-pack artifact manifest invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0052",
        "source-pack artifact shard metadata invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0053",
        "package manifest invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0054",
        "package manifest could not be read",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0055",
        "package lockfile invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0056",
        "package lockfile could not be read or written",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0057",
        "compiler execution failed",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0058",
        "source-pack progress state invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0059",
        "source-pack artifact store failed",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0060",
        "source-pack metadata store failed",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0061",
        "source-root input invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0062",
        "source-pack target invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0063",
        "source-pack work queue invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0064",
        "source-pack preparation incomplete",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0065",
        "source-pack preparation limit invalid",
        "package/import loading",
        DiagnosticPrimaryLabelPolicy::None,
    ),
    DiagnosticCodeInfo::error(
        "LNC0066",
        "parser execution failed",
        "parsing",
        DiagnosticPrimaryLabelPolicy::Required,
    ),
    DiagnosticCodeInfo::error(
        "LNC0067",
        "CLI operation failed",
        "tooling",
        DiagnosticPrimaryLabelPolicy::None,
    ),
];

/// Stable diagnostic categories used by registry and category metadata output.
///
/// Categories are intentionally broader than implementation modules so tools can
/// group related diagnostics across frontend, package loading, and target
/// backends without depending on compiler internals.
pub const DIAGNOSTIC_CATEGORIES: &[&str] = &[
    "module resolution",
    "name resolution",
    "native codegen",
    "package/import loading",
    "parsing",
    "runtime binding",
    "target codegen",
    "tooling",
    "trait solving",
    "type checking",
];

/// Schema name for the full diagnostic registry payload.
pub const DIAGNOSTIC_REGISTRY_SCHEMA_NAME: &str = "laniusc.diagnostics.registry";
/// Schema name for one `laniusc diagnostics explain` payload.
pub const DIAGNOSTIC_EXPLANATION_SCHEMA_NAME: &str = "laniusc.diagnostics.explanation";
/// Schema name for the diagnostic output-format registry payload.
pub const DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_NAME: &str = "laniusc.diagnostics.output-formats";
/// Version of the full diagnostic registry payload.
pub const DIAGNOSTIC_REGISTRY_SCHEMA_VERSION: u32 = 24;
/// Version of the diagnostic explanation payload.
pub const DIAGNOSTIC_EXPLANATION_SCHEMA_VERSION: u32 = 14;
/// Version of the diagnostic output-format registry payload.
pub const DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_VERSION: u32 = 9;
/// Default `--diagnostic-format` value.
pub const DEFAULT_DIAGNOSTIC_OUTPUT_FORMAT: &str = "text";
/// Accepted `--diagnostic-format` values in command-line spelling.
pub const DIAGNOSTIC_OUTPUT_FORMAT_NAMES: &[&str] = &["text", "json", "lsp-json"];
/// Example inputs accepted by diagnostic-code selector APIs.
pub const DIAGNOSTIC_CODE_SELECTOR_EXAMPLES: &[&str] = &[
    "LNC0018",
    "lnc0018",
    "error[LNC0018]: unsupported CLI option value",
];
/// Human-readable selector patterns accepted by diagnostic-code lookup APIs.
pub const DIAGNOSTIC_CODE_SELECTOR_PATTERNS: &[&str] = &[
    "LNCdddd",
    "lncdddd",
    "copied text containing one LNCdddd token",
];
/// CLI command that prints the compact diagnostic-code index.
pub const DIAGNOSTIC_CODE_INDEX_COMMAND: &str = "laniusc diagnostics codes";
/// CLI command that prints the full diagnostic registry.
pub const DIAGNOSTIC_REGISTRY_COMMAND: &str = "laniusc diagnostics registry";
/// Selector kinds accepted by runtime-service diagnostic metadata commands.
pub const RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS: &[&str] = &[
    "service_id",
    "service_name",
    "module_path",
    "capability_constant",
    "status_probe",
    "binding_probe",
    "api_name",
    "service_api_name",
];
/// Selector kinds accepted by runtime-bound API diagnostic metadata commands.
pub const RUNTIME_BOUND_API_SELECTOR_KINDS: &[&str] = &["api_name", "service_api_name"];

/// Top-level diagnostic registry payload printed by `laniusc diagnostics registry`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct DiagnosticRegistry {
    /// Payload schema version.
    pub schema_version: u32,
    /// Payload schema name.
    pub schema_name: &'static str,
    /// Stable diagnostic code rows.
    pub codes: &'static [DiagnosticCodeInfo],
    /// Stable category names.
    pub categories: &'static [&'static str],
    /// Diagnostic rows that describe intentionally unsupported language slices.
    pub unsupported_features: &'static [UnsupportedFeatureDiagnosticInfo],
    /// Diagnostic rows for target-codegen fail-closed boundaries.
    pub codegen_boundaries: &'static [CodegenBoundaryDiagnosticInfo],
    /// No-run contract for this metadata command.
    pub no_run_guards: DiagnosticExplanationNoRunGuards,
}

/// Registry of CLI diagnostic output formats.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct DiagnosticOutputFormatRegistry {
    /// Payload schema version.
    pub schema_version: u32,
    /// Payload schema name.
    pub schema_name: &'static str,
    /// CLI flag that selects a format.
    pub cli_flag: &'static str,
    /// Format used when the caller does not pass the flag.
    pub default_format: &'static str,
    /// Accepted command-line values.
    pub accepted_formats: &'static [&'static str],
    /// Detailed format contracts.
    pub formats: &'static [DiagnosticOutputFormatInfo],
    /// No-run contract for this metadata command.
    pub no_run_guards: DiagnosticExplanationNoRunGuards,
}

/// Metadata contract for one diagnostic renderer.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct DiagnosticOutputFormatInfo {
    /// Command-line format name.
    pub name: &'static str,
    /// Stream that receives diagnostics in this format.
    pub output_stream: &'static str,
    /// Shape of the emitted payload.
    pub payload: &'static str,
    /// Schema name for machine-readable payloads.
    pub payload_schema_name: Option<&'static str>,
    /// Schema version for machine-readable payloads.
    pub payload_schema_version: Option<u32>,
    /// Where the schema marker appears in the emitted payload.
    pub payload_schema_location: Option<&'static str>,
    /// Position encoding used by source locations in this format.
    pub position_encoding: &'static str,
    /// Whether the format includes a source-line snippet.
    pub includes_source_snippet: bool,
    /// Whether the format includes a language-server publish envelope.
    pub language_server_envelope: bool,
    /// Whether `laniusc check` may emit this format.
    pub check_mode_supported: bool,
    /// Whether formatter check diagnostics may emit this format.
    pub formatter_check_supported: bool,
    /// Short public description of the renderer contract.
    pub description: &'static str,
}

/// Explanation metadata for a diagnostic that marks an unsupported boundary.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct UnsupportedFeatureDiagnosticInfo {
    /// Diagnostic code that reports the boundary.
    pub code: &'static str,
    /// Name of the unsupported boundary.
    pub boundary: &'static str,
    /// Public explanation of what was rejected.
    pub summary: &'static str,
    /// Suggested next action for users or tools.
    pub next_step: &'static str,
}

/// Explanation metadata for a diagnostic that stops target-codegen safely.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct CodegenBoundaryDiagnosticInfo {
    /// Diagnostic code that reports the boundary.
    pub diagnostic_code: &'static str,
    /// Name of the backend or descriptor boundary.
    pub boundary: &'static str,
    /// Target triple or target family affected by the boundary.
    pub target: &'static str,
    /// Compilation stage that owns the failure.
    pub stage: &'static str,
    /// Policy for avoiding partially emitted target artifacts.
    pub partial_artifact_policy: &'static str,
    /// Whether target bytes may have been emitted before this diagnostic.
    pub target_bytes_emitted: bool,
    /// Diagnostics-only command that can be used to avoid codegen.
    pub diagnostics_only_command: &'static str,
    /// Alternate emit target, if one currently exists for the boundary.
    pub fallback_emit: Option<&'static str>,
}

/// Metadata for one runtime service boundary exposed by stdlib declarations.
///
/// Runtime services are known to the compiler but intentionally fail closed when
/// there is no executable host binding. The metadata lets tooling explain that
/// boundary without compiling source.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct RuntimeServiceBoundaryDiagnosticInfo {
    /// Diagnostic code that reports runtime-service binding failures.
    pub diagnostic_code: &'static str,
    /// Stable runtime service id.
    pub service_id: u32,
    /// Human-readable service name.
    pub service_name: &'static str,
    /// Stdlib module that owns the service.
    pub module_path: &'static str,
    /// Capability constant exposed by the stdlib contract.
    pub capability_constant: &'static str,
    /// Query function that reports the service status.
    pub status_probe: &'static str,
    /// Query function that reports whether a runtime binding is required.
    pub binding_probe: &'static str,
    /// Selector kinds accepted by service metadata lookup commands.
    pub accepted_selector_kinds: &'static [&'static str],
    /// Current compiler/runtime status for the service.
    pub current_status: &'static str,
    /// Whether calls through the service are currently executable.
    pub executable: bool,
}

/// Metadata for one stdlib API that crosses a runtime or compiler-host boundary.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct RuntimeBoundApiDiagnosticInfo {
    /// Diagnostic code that reports runtime-bound API failures.
    pub diagnostic_code: &'static str,
    /// Stable runtime service id.
    pub service_id: u32,
    /// Human-readable service name.
    pub service_name: &'static str,
    /// Capability constant for the owning service.
    pub service_capability_constant: &'static str,
    /// Stdlib module that owns the service.
    pub service_module_path: &'static str,
    /// Query function that reports the service status.
    pub service_status_probe: &'static str,
    /// Query function that reports whether the service needs a binding.
    pub service_binding_probe: &'static str,
    /// Current compiler/runtime status for the owning service.
    pub service_current_status: &'static str,
    /// Whether the owning service is currently executable.
    pub service_executable: bool,
    /// Module path containing the API.
    pub module_path: &'static str,
    /// Fully qualified API name.
    pub api_name: &'static str,
    /// Runtime ABI family expected by the API, or compiler primitive family for
    /// APIs backed directly by codegen.
    pub extern_abi: &'static str,
    /// Query function that reports whether the API is executable.
    pub executable_probe: &'static str,
    /// Query function that reports whether the API needs a binding.
    pub binding_probe: &'static str,
    /// Selector kinds accepted by API metadata lookup commands.
    pub accepted_selector_kinds: &'static [&'static str],
    /// Current compiler/runtime status for the API.
    pub current_status: &'static str,
    /// Whether calls to this API are currently executable.
    pub executable: bool,
}

/// No-run contract for metadata-only diagnostic commands.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct DiagnosticExplanationNoRunGuards {
    /// Whether the command compiles source code.
    pub source_compilation: bool,
    /// Whether the command scans user source files.
    pub source_scanning: bool,
    /// Whether the command creates a GPU device.
    pub gpu_device_creation: bool,
    /// Whether the command performs target codegen.
    pub target_codegen: bool,
}

/// Machine-readable explanation for one diagnostic code.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct DiagnosticExplanation {
    /// Payload schema version.
    pub schema_version: u32,
    /// Payload schema name.
    pub schema_name: &'static str,
    /// Registry version used to interpret embedded registry rows.
    pub registry_schema_version: u32,
    /// Canonical diagnostic code requested by the caller.
    pub requested_code: String,
    /// CLI command that can reproduce this explanation.
    pub explain_command: String,
    /// Whether `requested_code` appears in the current registry.
    pub known: bool,
    /// Registry row for the requested code, if it is known.
    pub diagnostic: Option<DiagnosticCodeInfo>,
    /// Unsupported-feature metadata for the code, if applicable.
    pub unsupported_feature: Option<UnsupportedFeatureDiagnosticInfo>,
    /// Codegen-boundary metadata for the code, if applicable.
    pub codegen_boundary: Option<CodegenBoundaryDiagnosticInfo>,
    /// Runtime service boundaries attached to the code, if applicable.
    pub runtime_service_boundaries: Option<&'static [RuntimeServiceBoundaryDiagnosticInfo]>,
    /// Runtime-bound APIs attached to the code, if applicable.
    pub runtime_bound_apis: Option<&'static [RuntimeBoundApiDiagnosticInfo]>,
    /// Example selectors accepted by code lookup commands.
    pub accepted_selector_examples: &'static [&'static str],
    /// Selector patterns accepted by code lookup commands.
    pub accepted_selector_patterns: &'static [&'static str],
    /// CLI command that lists diagnostic codes.
    pub code_index_command: &'static str,
    /// CLI command that prints the full registry.
    pub registry_command: &'static str,
    /// No-run contract for this metadata command.
    pub no_run_guards: DiagnosticExplanationNoRunGuards,
}

/// Diagnostic codes that intentionally describe unsupported compiler slices.
pub const UNSUPPORTED_FEATURE_DIAGNOSTICS: &[UnsupportedFeatureDiagnosticInfo] = &[
    UnsupportedFeatureDiagnosticInfo {
        code: "LNC0011",
        boundary: "import form",
        summary: "the module resolver understood the import position but rejected the import shape",
        next_step: "use module-path imports such as `import app::module;`; quoted imports are not supported in this edition",
    },
    UnsupportedFeatureDiagnosticInfo {
        code: "LNC0012",
        boundary: "import path depth",
        summary: "the import path exceeded the compiler's currently supported module depth",
        next_step: "shorten or flatten the import path before compiling with this edition",
    },
    UnsupportedFeatureDiagnosticInfo {
        code: "LNC0014",
        boundary: "module path depth",
        summary: "the declared module path exceeded the compiler's currently supported module depth",
        next_step: "shorten or flatten the module declaration before compiling with this edition",
    },
    UnsupportedFeatureDiagnosticInfo {
        code: "LNC0017",
        boundary: "x86 backend",
        summary: "the program reached a native-codegen construct outside the current x86 lowering slice and is rejected instead of emitting a partial instruction prefix",
        next_step: "use `laniusc check` for diagnostics-only validation or `--emit=wasm` until this construct is covered by x86 lowering",
    },
    UnsupportedFeatureDiagnosticInfo {
        code: "LNC0022",
        boundary: "linked-output contract descriptor",
        summary: "descriptor-mode linked output is expected to be JSON contract metadata, not executable bytes or incoherent descriptor data",
        next_step: "treat descriptor-mode linked output as JSON contract metadata; use non-descriptor compilation when target bytes are required",
    },
    UnsupportedFeatureDiagnosticInfo {
        code: "LNC0024",
        boundary: "source-root package boundary",
        summary: "source-root loading rejected an import edge that crosses from stdlib roots back into package/user source roots",
        next_step: "keep stdlib modules independent from package/user roots; move shared APIs into stdlib roots or pass package sources through package manifest/lockfile metadata",
    },
    UnsupportedFeatureDiagnosticInfo {
        code: "LNC0036",
        boundary: "WASM backend",
        summary: "the program reached a WASM-codegen construct outside the current WASM lowering support and is rejected instead of emitting a partial module prefix",
        next_step: "use `laniusc check` for diagnostics-only validation until this construct is covered by WASM lowering",
    },
    UnsupportedFeatureDiagnosticInfo {
        code: "LNC0038",
        boundary: "runtime service binding",
        summary: "the program reached a stdlib or host API whose runtime service descriptor is known but not bound by the current linker/runtime contract",
        next_step: "treat the API as contract metadata only, check the matching `*_requires_runtime_binding()` helper, or supply a future runtime binding before emitting executable output",
    },
];

/// Fail-closed target-codegen boundaries exposed through diagnostic metadata.
pub const CODEGEN_BOUNDARY_DIAGNOSTICS: &[CodegenBoundaryDiagnosticInfo] = &[
    CodegenBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0017",
        boundary: "x86 backend",
        target: "x86_64",
        stage: "native codegen lowering",
        partial_artifact_policy: "fail-closed before emitting a partial instruction prefix",
        target_bytes_emitted: false,
        diagnostics_only_command: "laniusc check",
        fallback_emit: Some("wasm"),
    },
    CodegenBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0036",
        boundary: "WASM backend",
        target: "wasm",
        stage: "WASM codegen lowering",
        partial_artifact_policy: "fail-closed before emitting a partial module prefix",
        target_bytes_emitted: false,
        diagnostics_only_command: "laniusc check",
        fallback_emit: None,
    },
];

/// Shared no-run guard metadata for diagnostic registry/explanation commands.
pub const DIAGNOSTIC_EXPLANATION_NO_RUN_GUARDS: DiagnosticExplanationNoRunGuards =
    DiagnosticExplanationNoRunGuards {
        source_compilation: false,
        source_scanning: false,
        gpu_device_creation: false,
        target_codegen: false,
    };

/// Runtime services that are known but not executable without host bindings.
pub const RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS: &[RuntimeServiceBoundaryDiagnosticInfo] = &[
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 1,
        service_name: "allocator",
        module_path: "alloc::allocator",
        capability_constant: "ALLOCATOR_HAS_RUNTIME_BINDING",
        status_probe: "allocator_service_status()",
        binding_probe: "allocator_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 2,
        service_name: "filesystem",
        module_path: "std::fs",
        capability_constant: "FILESYSTEM_HAS_RUNTIME_BINDING",
        status_probe: "filesystem_service_status()",
        binding_probe: "filesystem_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 3,
        service_name: "stdio",
        module_path: "std::io",
        capability_constant: "STDIO_HAS_RUNTIME_BINDING",
        status_probe: "stdio_service_status()",
        binding_probe: "stdio_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 4,
        service_name: "clock",
        module_path: "std::time",
        capability_constant: "CLOCK_HAS_RUNTIME_BINDING",
        status_probe: "clock_service_status()",
        binding_probe: "clock_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 5,
        service_name: "network",
        module_path: "std::net",
        capability_constant: "NETWORK_HAS_RUNTIME_BINDING",
        status_probe: "network_service_status()",
        binding_probe: "network_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 6,
        service_name: "panic hook",
        module_path: "core::panic",
        capability_constant: "PANIC_HOOK_HAS_RUNTIME_BINDING",
        status_probe: "panic_hook_service_status()",
        binding_probe: "panic_hook_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 7,
        service_name: "host services",
        module_path: "std::host",
        capability_constant: "HOST_SERVICES_HAS_RUNTIME_BINDING",
        status_probe: "host_services_service_status()",
        binding_probe: "host_services_require_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 8,
        service_name: "threads",
        module_path: "std::thread",
        capability_constant: "THREAD_HAS_RUNTIME_BINDING",
        status_probe: "thread_service_status()",
        binding_probe: "thread_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 9,
        service_name: "secure RNG",
        module_path: "std::random",
        capability_constant: "RANDOM_HAS_RUNTIME_BINDING",
        status_probe: "random_service_status()",
        binding_probe: "random_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 10,
        service_name: "GPU host service",
        module_path: "std::gpu",
        capability_constant: "GPU_HAS_RUNTIME_BINDING",
        status_probe: "gpu_service_status()",
        binding_probe: "gpu_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 11,
        service_name: "process",
        module_path: "std::process",
        capability_constant: "PROCESS_HAS_RUNTIME_BINDING",
        status_probe: "process_service_status()",
        binding_probe: "process_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 12,
        service_name: "environment",
        module_path: "std::env",
        capability_constant: "ENV_HAS_RUNTIME_BINDING",
        status_probe: "env_service_status()",
        binding_probe: "env_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
    RuntimeServiceBoundaryDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id: 13,
        service_name: "test harness",
        module_path: "test::harness",
        capability_constant: "TEST_HARNESS_HAS_RUNTIME_BINDING",
        status_probe: "test_harness_service_status()",
        binding_probe: "test_harness_requires_runtime_binding()",
        accepted_selector_kinds: RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
        current_status: "known-unbound",
        executable: false,
    },
];

const fn runtime_bound_api(
    service_id: u32,
    service_name: &'static str,
    module_path: &'static str,
    api_name: &'static str,
    executable_probe: &'static str,
    binding_probe: &'static str,
) -> RuntimeBoundApiDiagnosticInfo {
    runtime_api(
        service_id,
        service_name,
        module_path,
        api_name,
        runtime_service_extern_abi(service_id),
        executable_probe,
        binding_probe,
        "known-unbound",
        false,
    )
}

const fn executable_runtime_api(
    service_id: u32,
    service_name: &'static str,
    module_path: &'static str,
    api_name: &'static str,
    extern_abi: &'static str,
    executable_probe: &'static str,
    binding_probe: &'static str,
) -> RuntimeBoundApiDiagnosticInfo {
    runtime_api(
        service_id,
        service_name,
        module_path,
        api_name,
        extern_abi,
        executable_probe,
        binding_probe,
        "executable-compiler-primitive",
        true,
    )
}

const fn runtime_api(
    service_id: u32,
    service_name: &'static str,
    module_path: &'static str,
    api_name: &'static str,
    extern_abi: &'static str,
    executable_probe: &'static str,
    binding_probe: &'static str,
    current_status: &'static str,
    executable: bool,
) -> RuntimeBoundApiDiagnosticInfo {
    RuntimeBoundApiDiagnosticInfo {
        diagnostic_code: "LNC0038",
        service_id,
        service_name,
        service_capability_constant: runtime_service_capability_constant(service_id),
        service_module_path: runtime_service_module_path(service_id),
        service_status_probe: runtime_service_status_probe(service_id),
        service_binding_probe: runtime_service_binding_probe(service_id),
        service_current_status: runtime_service_current_status(service_id),
        service_executable: runtime_service_executable(service_id),
        module_path,
        api_name,
        extern_abi,
        executable_probe,
        binding_probe,
        accepted_selector_kinds: RUNTIME_BOUND_API_SELECTOR_KINDS,
        current_status,
        executable,
    }
}

const fn runtime_service_capability_constant(service_id: u32) -> &'static str {
    match service_id {
        1 => "ALLOCATOR_HAS_RUNTIME_BINDING",
        2 => "FILESYSTEM_HAS_RUNTIME_BINDING",
        3 => "STDIO_HAS_RUNTIME_BINDING",
        4 => "CLOCK_HAS_RUNTIME_BINDING",
        5 => "NETWORK_HAS_RUNTIME_BINDING",
        6 => "PANIC_HOOK_HAS_RUNTIME_BINDING",
        7 => "HOST_SERVICES_HAS_RUNTIME_BINDING",
        8 => "THREAD_HAS_RUNTIME_BINDING",
        9 => "RANDOM_HAS_RUNTIME_BINDING",
        10 => "GPU_HAS_RUNTIME_BINDING",
        11 => "PROCESS_HAS_RUNTIME_BINDING",
        12 => "ENV_HAS_RUNTIME_BINDING",
        13 => "TEST_HARNESS_HAS_RUNTIME_BINDING",
        _ => "UNKNOWN_RUNTIME_SERVICE_HAS_RUNTIME_BINDING",
    }
}

const fn runtime_service_module_path(service_id: u32) -> &'static str {
    match service_id {
        1 => "alloc::allocator",
        2 => "std::fs",
        3 => "std::io",
        4 => "std::time",
        5 => "std::net",
        6 => "core::panic",
        7 => "std::host",
        8 => "std::thread",
        9 => "std::random",
        10 => "std::gpu",
        11 => "std::process",
        12 => "std::env",
        13 => "test::harness",
        _ => "unknown::runtime_service",
    }
}

const fn runtime_service_status_probe(service_id: u32) -> &'static str {
    match service_id {
        1 => "allocator_service_status()",
        2 => "filesystem_service_status()",
        3 => "stdio_service_status()",
        4 => "clock_service_status()",
        5 => "network_service_status()",
        6 => "panic_hook_service_status()",
        7 => "host_services_service_status()",
        8 => "thread_service_status()",
        9 => "random_service_status()",
        10 => "gpu_service_status()",
        11 => "process_service_status()",
        12 => "env_service_status()",
        13 => "test_harness_service_status()",
        _ => "unknown_runtime_service_status()",
    }
}

const fn runtime_service_binding_probe(service_id: u32) -> &'static str {
    match service_id {
        1 => "allocator_requires_runtime_binding()",
        2 => "filesystem_requires_runtime_binding()",
        3 => "stdio_requires_runtime_binding()",
        4 => "clock_requires_runtime_binding()",
        5 => "network_requires_runtime_binding()",
        6 => "panic_hook_requires_runtime_binding()",
        7 => "host_services_require_runtime_binding()",
        8 => "thread_requires_runtime_binding()",
        9 => "random_requires_runtime_binding()",
        10 => "gpu_requires_runtime_binding()",
        11 => "process_requires_runtime_binding()",
        12 => "env_requires_runtime_binding()",
        13 => "test_harness_requires_runtime_binding()",
        _ => "unknown_runtime_service_requires_runtime_binding()",
    }
}

const fn runtime_service_current_status(service_id: u32) -> &'static str {
    match service_id {
        1..=13 => "known-unbound",
        _ => "unknown",
    }
}

const fn runtime_service_executable(_service_id: u32) -> bool {
    false
}

const fn runtime_service_extern_abi(service_id: u32) -> &'static str {
    match service_id {
        1 => "lanius_alloc",
        2 | 3 | 4 | 5 | 8 | 9 | 10 | 11 | 12 => "lanius_std",
        6 => "lanius_panic",
        13 => "lanius_test",
        _ => "unknown_runtime_service_abi",
    }
}

/// Stdlib APIs that cross runtime-service boundaries or compiler-host primitives.
pub const RUNTIME_BOUND_API_DIAGNOSTICS: &[RuntimeBoundApiDiagnosticInfo] = &[
    executable_runtime_api(
        1,
        "allocator",
        "alloc::allocator",
        "alloc::allocator::alloc",
        "lanius_alloc",
        "alloc_is_executable()",
        "alloc_requires_runtime_binding()",
    ),
    runtime_bound_api(
        1,
        "allocator",
        "alloc::allocator",
        "alloc::allocator::realloc",
        "realloc_is_executable()",
        "realloc_requires_runtime_binding()",
    ),
    executable_runtime_api(
        1,
        "allocator",
        "alloc::allocator",
        "alloc::allocator::dealloc",
        "lanius_alloc",
        "dealloc_is_executable()",
        "dealloc_requires_runtime_binding()",
    ),
    runtime_bound_api(
        1,
        "allocator",
        "alloc::allocator",
        "alloc::allocator::alloc_failed",
        "alloc_failed_is_executable()",
        "alloc_failed_requires_runtime_binding()",
    ),
    runtime_bound_api(
        2,
        "filesystem",
        "std::fs",
        "std::fs::open_read",
        "open_read_is_executable()",
        "open_read_requires_runtime_binding()",
    ),
    runtime_bound_api(
        2,
        "filesystem",
        "std::fs",
        "std::fs::open_write",
        "open_write_is_executable()",
        "open_write_requires_runtime_binding()",
    ),
    runtime_bound_api(
        2,
        "filesystem",
        "std::fs",
        "std::fs::open_append",
        "open_append_is_executable()",
        "open_append_requires_runtime_binding()",
    ),
    runtime_bound_api(
        2,
        "filesystem",
        "std::fs",
        "std::fs::close",
        "close_is_executable()",
        "close_requires_runtime_binding()",
    ),
    runtime_bound_api(
        2,
        "filesystem",
        "std::fs",
        "std::fs::read",
        "read_is_executable()",
        "read_requires_runtime_binding()",
    ),
    runtime_bound_api(
        2,
        "filesystem",
        "std::fs",
        "std::fs::write",
        "write_is_executable()",
        "write_requires_runtime_binding()",
    ),
    runtime_bound_api(
        2,
        "filesystem",
        "std::fs",
        "std::fs::remove_file",
        "path_mutation_api_is_executable()",
        "path_mutation_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        2,
        "filesystem",
        "std::fs",
        "std::fs::create_dir",
        "path_mutation_api_is_executable()",
        "path_mutation_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        2,
        "filesystem",
        "std::fs",
        "std::fs::remove_dir",
        "path_mutation_api_is_executable()",
        "path_mutation_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        2,
        "filesystem",
        "std::fs",
        "std::fs::rename",
        "path_mutation_api_is_executable()",
        "path_mutation_api_requires_runtime_binding()",
    ),
    executable_runtime_api(
        3,
        "stdio",
        "std::io",
        "std::io::write_stdout",
        "compiler_host_stdio",
        "write_stdout_is_executable()",
        "write_stdout_requires_runtime_binding()",
    ),
    executable_runtime_api(
        3,
        "stdio",
        "std::io",
        "std::io::write_stderr",
        "compiler_host_stdio",
        "write_stderr_is_executable()",
        "write_stderr_requires_runtime_binding()",
    ),
    executable_runtime_api(
        3,
        "stdio",
        "std::io",
        "std::io::read_stdin",
        "compiler_host_stdio",
        "read_stdin_is_executable()",
        "read_stdin_requires_runtime_binding()",
    ),
    runtime_bound_api(
        3,
        "stdio",
        "std::io",
        "std::io::flush_stdout",
        "flush_stdout_is_executable()",
        "flush_stdout_requires_runtime_binding()",
    ),
    runtime_bound_api(
        3,
        "stdio",
        "std::io",
        "std::io::flush_stderr",
        "flush_stderr_is_executable()",
        "flush_stderr_requires_runtime_binding()",
    ),
    executable_runtime_api(
        3,
        "stdio",
        "std::io",
        "std::io::print_i32",
        "compiler_print_i32",
        "print_i32_is_executable()",
        "print_i32_requires_runtime_binding()",
    ),
    runtime_bound_api(
        4,
        "clock",
        "std::time",
        "std::time::monotonic_now_ns",
        "monotonic_now_ns_is_executable()",
        "monotonic_now_ns_requires_runtime_binding()",
    ),
    runtime_bound_api(
        4,
        "clock",
        "std::time",
        "std::time::system_now_unix_ms",
        "system_now_unix_ms_is_executable()",
        "system_now_unix_ms_requires_runtime_binding()",
    ),
    runtime_bound_api(
        4,
        "clock",
        "std::time",
        "std::time::sleep_ms",
        "sleep_ms_is_executable()",
        "sleep_ms_requires_runtime_binding()",
    ),
    runtime_bound_api(
        5,
        "network",
        "std::net",
        "std::net::tcp_connect",
        "tcp_api_is_executable()",
        "tcp_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        5,
        "network",
        "std::net",
        "std::net::tcp_bind",
        "tcp_api_is_executable()",
        "tcp_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        5,
        "network",
        "std::net",
        "std::net::tcp_listen",
        "tcp_api_is_executable()",
        "tcp_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        5,
        "network",
        "std::net",
        "std::net::tcp_accept",
        "tcp_api_is_executable()",
        "tcp_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        5,
        "network",
        "std::net",
        "std::net::tcp_close",
        "tcp_api_is_executable()",
        "tcp_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        5,
        "network",
        "std::net",
        "std::net::tcp_send",
        "tcp_api_is_executable()",
        "tcp_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        5,
        "network",
        "std::net",
        "std::net::tcp_recv",
        "tcp_api_is_executable()",
        "tcp_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        5,
        "network",
        "std::net",
        "std::net::udp_bind",
        "udp_api_is_executable()",
        "udp_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        5,
        "network",
        "std::net",
        "std::net::udp_send_to",
        "udp_api_is_executable()",
        "udp_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        5,
        "network",
        "std::net",
        "std::net::udp_recv_from",
        "udp_api_is_executable()",
        "udp_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        6,
        "panic hook",
        "core::panic",
        "core::panic::panic",
        "panic_is_executable()",
        "panic_requires_runtime_binding()",
    ),
    runtime_bound_api(
        6,
        "panic hook",
        "core::panic",
        "core::panic::unreachable",
        "unreachable_is_executable()",
        "unreachable_requires_runtime_binding()",
    ),
    runtime_bound_api(
        8,
        "threads",
        "std::thread",
        "std::thread::spawn",
        "thread_spawn_is_executable()",
        "thread_spawn_requires_runtime_binding()",
    ),
    runtime_bound_api(
        8,
        "threads",
        "std::thread",
        "std::thread::join",
        "thread_join_is_executable()",
        "thread_join_requires_runtime_binding()",
    ),
    runtime_bound_api(
        8,
        "threads",
        "std::thread",
        "std::thread::yield_now",
        "thread_yield_is_executable()",
        "thread_yield_requires_runtime_binding()",
    ),
    runtime_bound_api(
        8,
        "threads",
        "std::thread",
        "std::thread::current_id",
        "thread_current_id_is_executable()",
        "thread_current_id_requires_runtime_binding()",
    ),
    runtime_bound_api(
        9,
        "secure RNG",
        "std::random",
        "std::random::fill_secure_bytes",
        "fill_secure_bytes_is_executable()",
        "fill_secure_bytes_requires_runtime_binding()",
    ),
    executable_runtime_api(
        9,
        "secure RNG",
        "std::random",
        "std::random::secure_u32",
        "lanius_std",
        "secure_u32_is_executable()",
        "secure_u32_requires_runtime_binding()",
    ),
    runtime_bound_api(
        10,
        "GPU host service",
        "std::gpu",
        "std::gpu::buffer_alloc",
        "gpu_buffer_api_is_executable()",
        "gpu_buffer_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        10,
        "GPU host service",
        "std::gpu",
        "std::gpu::buffer_free",
        "gpu_buffer_api_is_executable()",
        "gpu_buffer_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        10,
        "GPU host service",
        "std::gpu",
        "std::gpu::buffer_write",
        "gpu_buffer_api_is_executable()",
        "gpu_buffer_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        10,
        "GPU host service",
        "std::gpu",
        "std::gpu::buffer_read",
        "gpu_buffer_api_is_executable()",
        "gpu_buffer_api_requires_runtime_binding()",
    ),
    runtime_bound_api(
        10,
        "GPU host service",
        "std::gpu",
        "std::gpu::dispatch_1d",
        "gpu_dispatch_api_is_executable()",
        "gpu_dispatch_api_requires_runtime_binding()",
    ),
    executable_runtime_api(
        11,
        "process",
        "std::process",
        "std::process::argc",
        "lanius_std",
        "argc_is_executable()",
        "argc_requires_runtime_binding()",
    ),
    executable_runtime_api(
        11,
        "process",
        "std::process",
        "std::process::arg_len",
        "lanius_std",
        "arg_len_is_executable()",
        "arg_len_requires_runtime_binding()",
    ),
    executable_runtime_api(
        11,
        "process",
        "std::process",
        "std::process::arg_read",
        "lanius_std",
        "arg_read_is_executable()",
        "arg_read_requires_runtime_binding()",
    ),
    runtime_bound_api(
        11,
        "process",
        "std::process",
        "std::process::set_exit_code",
        "set_exit_code_is_executable()",
        "set_exit_code_requires_runtime_binding()",
    ),
    executable_runtime_api(
        11,
        "process",
        "std::process",
        "std::process::exit",
        "lanius_std",
        "exit_is_executable()",
        "exit_requires_runtime_binding()",
    ),
    runtime_bound_api(
        12,
        "environment",
        "std::env",
        "std::env::var_len",
        "var_len_is_executable()",
        "var_len_requires_runtime_binding()",
    ),
    runtime_bound_api(
        12,
        "environment",
        "std::env",
        "std::env::var_read",
        "var_read_is_executable()",
        "var_read_requires_runtime_binding()",
    ),
    runtime_bound_api(
        12,
        "environment",
        "std::env",
        "std::env::var_count",
        "var_count_is_executable()",
        "var_count_requires_runtime_binding()",
    ),
    runtime_bound_api(
        12,
        "environment",
        "std::env",
        "std::env::var_key_len",
        "var_key_len_is_executable()",
        "var_key_len_requires_runtime_binding()",
    ),
    runtime_bound_api(
        12,
        "environment",
        "std::env",
        "std::env::var_key_read",
        "var_key_read_is_executable()",
        "var_key_read_requires_runtime_binding()",
    ),
    runtime_bound_api(
        12,
        "environment",
        "std::env",
        "std::env::current_dir_len",
        "current_dir_len_is_executable()",
        "current_dir_len_requires_runtime_binding()",
    ),
    runtime_bound_api(
        12,
        "environment",
        "std::env",
        "std::env::current_dir_read",
        "current_dir_read_is_executable()",
        "current_dir_read_requires_runtime_binding()",
    ),
];

/// Detailed metadata for each accepted diagnostic output format.
pub const DIAGNOSTIC_OUTPUT_FORMATS: &[DiagnosticOutputFormatInfo] = &[
    DiagnosticOutputFormatInfo {
        name: "text",
        output_stream: "stderr",
        payload: "human-readable diagnostic text",
        payload_schema_name: None,
        payload_schema_version: None,
        payload_schema_location: None,
        position_encoding: "one-based source line and column",
        includes_source_snippet: true,
        language_server_envelope: false,
        check_mode_supported: true,
        formatter_check_supported: true,
        description: "default CLI renderer with code, optional path/source snippet/label, and notes",
    },
    DiagnosticOutputFormatInfo {
        name: "json",
        output_stream: "stderr",
        payload: "Diagnostic JSON object",
        payload_schema_name: Some(DIAGNOSTIC_JSON_SCHEMA_NAME),
        payload_schema_version: Some(DIAGNOSTIC_JSON_SCHEMA_VERSION),
        payload_schema_location: Some("top-level"),
        position_encoding: "one-based source line and column",
        includes_source_snippet: true,
        language_server_envelope: false,
        check_mode_supported: true,
        formatter_check_supported: true,
        description: "diagnostic object preserving payload schema name/version, registry schema version, severity, stable code/title/category/primary-label policy/help, explain command, message, optional primary_label with source path/line/column/byte-span context, and notes",
    },
    DiagnosticOutputFormatInfo {
        name: "lsp-json",
        output_stream: "stderr",
        payload: "LSP Diagnostic JSON object",
        payload_schema_name: Some(LSP_DIAGNOSTIC_DATA_SCHEMA_NAME),
        payload_schema_version: Some(LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION),
        payload_schema_location: Some("data"),
        position_encoding: LSP_POSITION_ENCODING,
        includes_source_snippet: false,
        language_server_envelope: false,
        check_mode_supported: true,
        formatter_check_supported: true,
        description: "single LSP Diagnostic-shaped object with zero-based range, numeric severity, code, source, message, and versioned Lanius schema name/title/category/notes/help/explain-command/source-byte-span metadata under data",
    },
];

/// Looks up a diagnostic registry row by code, ignoring surrounding whitespace and case.
pub fn diagnostic_code_info(code: &str) -> Option<&'static DiagnosticCodeInfo> {
    let code = code.trim();
    DIAGNOSTIC_CODE_REGISTRY
        .iter()
        .find(|diagnostic| diagnostic.code.eq_ignore_ascii_case(code))
}

fn canonical_diagnostic_code(code: &str) -> String {
    if let Some(diagnostic) = diagnostic_code_info(code) {
        return diagnostic.code.to_string();
    }

    let code = diagnostic_code_token(code).unwrap_or_else(|| code.trim());
    diagnostic_code_info(code)
        .map(|diagnostic| diagnostic.code.to_string())
        .unwrap_or_else(|| code.trim().to_ascii_uppercase())
}

fn diagnostic_code_token(input: &str) -> Option<&str> {
    let input = input.trim();
    let bytes = input.as_bytes();
    for start in 0..bytes.len().saturating_sub(6) {
        let end = start + 7;
        let Some(candidate) = input.get(start..end) else {
            continue;
        };
        if !diagnostic_code_token_has_boundary(bytes, start, end) {
            continue;
        }
        let candidate_bytes = candidate.as_bytes();
        if candidate_bytes[0].eq_ignore_ascii_case(&b'L')
            && candidate_bytes[1].eq_ignore_ascii_case(&b'N')
            && candidate_bytes[2].eq_ignore_ascii_case(&b'C')
            && candidate_bytes[3..].iter().all(u8::is_ascii_digit)
        {
            return Some(candidate);
        }
    }
    None
}

fn diagnostic_code_token_has_boundary(bytes: &[u8], start: usize, end: usize) -> bool {
    let left_boundary = start == 0 || !bytes[start - 1].is_ascii_alphanumeric();
    let right_boundary = end == bytes.len() || !bytes[end].is_ascii_alphanumeric();
    left_boundary && right_boundary
}

/// Returns whether `category` is one of the stable diagnostic categories.
pub fn diagnostic_category_is_registered(category: &str) -> bool {
    DIAGNOSTIC_CATEGORIES.contains(&category)
}

/// Looks up unsupported-feature metadata for a diagnostic code selector.
pub fn unsupported_feature_diagnostic_info(
    code: &str,
) -> Option<&'static UnsupportedFeatureDiagnosticInfo> {
    let code = canonical_diagnostic_code(code);
    UNSUPPORTED_FEATURE_DIAGNOSTICS
        .iter()
        .find(|diagnostic| diagnostic.code == code)
}

/// Looks up target-codegen boundary metadata for a diagnostic code selector.
pub fn codegen_boundary_diagnostic_info(
    code: &str,
) -> Option<&'static CodegenBoundaryDiagnosticInfo> {
    let code = canonical_diagnostic_code(code);
    CODEGEN_BOUNDARY_DIAGNOSTICS
        .iter()
        .find(|diagnostic| diagnostic.diagnostic_code == code)
}

/// Looks up runtime-service boundary metadata by stable service id.
pub fn runtime_service_boundary_diagnostic_info(
    service_id: u32,
) -> Option<&'static RuntimeServiceBoundaryDiagnosticInfo> {
    RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS
        .iter()
        .find(|diagnostic| diagnostic.service_id == service_id)
}

/// Looks up runtime-bound API metadata by fully qualified API name.
pub fn runtime_bound_api_diagnostic_info(
    api_name: &str,
) -> Option<&'static RuntimeBoundApiDiagnosticInfo> {
    RUNTIME_BOUND_API_DIAGNOSTICS
        .iter()
        .find(|diagnostic| diagnostic.api_name == api_name)
}

/// Serializes runtime-service boundary metadata as pretty JSON.
pub fn runtime_service_boundary_diagnostics_json_pretty() -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS)
}

/// Serializes runtime-bound API metadata as pretty JSON.
pub fn runtime_bound_api_diagnostics_json_pretty() -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(RUNTIME_BOUND_API_DIAGNOSTICS)
}

/// Builds the full diagnostic registry payload.
pub fn diagnostic_registry() -> DiagnosticRegistry {
    DiagnosticRegistry {
        schema_version: DIAGNOSTIC_REGISTRY_SCHEMA_VERSION,
        schema_name: DIAGNOSTIC_REGISTRY_SCHEMA_NAME,
        codes: DIAGNOSTIC_CODE_REGISTRY,
        categories: DIAGNOSTIC_CATEGORIES,
        unsupported_features: UNSUPPORTED_FEATURE_DIAGNOSTICS,
        codegen_boundaries: CODEGEN_BOUNDARY_DIAGNOSTICS,
        no_run_guards: DIAGNOSTIC_EXPLANATION_NO_RUN_GUARDS,
    }
}

/// Builds the diagnostic output-format registry payload.
pub fn diagnostic_output_formats() -> DiagnosticOutputFormatRegistry {
    DiagnosticOutputFormatRegistry {
        schema_version: DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_VERSION,
        schema_name: DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_NAME,
        cli_flag: "--diagnostic-format",
        default_format: DEFAULT_DIAGNOSTIC_OUTPUT_FORMAT,
        accepted_formats: DIAGNOSTIC_OUTPUT_FORMAT_NAMES,
        formats: DIAGNOSTIC_OUTPUT_FORMATS,
        no_run_guards: DIAGNOSTIC_EXPLANATION_NO_RUN_GUARDS,
    }
}

/// Serializes the full diagnostic registry as pretty JSON.
pub fn diagnostic_registry_json_pretty() -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(&diagnostic_registry())
}

/// Serializes the diagnostic output-format registry as pretty JSON.
pub fn diagnostic_output_formats_json_pretty() -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(&diagnostic_output_formats())
}

/// Builds a machine-readable explanation for a diagnostic code selector.
///
/// Selectors may be canonical codes, differently cased codes, or copied
/// diagnostic text containing one `LNC####` token.
pub fn diagnostic_explanation(code: &str) -> DiagnosticExplanation {
    let requested_code = canonical_diagnostic_code(code);
    let diagnostic = diagnostic_code_info(&requested_code).copied();
    let runtime_service_boundaries =
        (requested_code == "LNC0038").then_some(RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS);
    let runtime_bound_apis = (requested_code == "LNC0038").then_some(RUNTIME_BOUND_API_DIAGNOSTICS);
    DiagnosticExplanation {
        schema_version: DIAGNOSTIC_EXPLANATION_SCHEMA_VERSION,
        schema_name: DIAGNOSTIC_EXPLANATION_SCHEMA_NAME,
        registry_schema_version: DIAGNOSTIC_REGISTRY_SCHEMA_VERSION,
        requested_code: requested_code.clone(),
        explain_command: diagnostic_explain_command(&requested_code),
        known: diagnostic.is_some(),
        diagnostic,
        unsupported_feature: unsupported_feature_diagnostic_info(&requested_code).copied(),
        codegen_boundary: codegen_boundary_diagnostic_info(&requested_code).copied(),
        runtime_service_boundaries,
        runtime_bound_apis,
        accepted_selector_examples: DIAGNOSTIC_CODE_SELECTOR_EXAMPLES,
        accepted_selector_patterns: DIAGNOSTIC_CODE_SELECTOR_PATTERNS,
        code_index_command: DIAGNOSTIC_CODE_INDEX_COMMAND,
        registry_command: DIAGNOSTIC_REGISTRY_COMMAND,
        no_run_guards: DIAGNOSTIC_EXPLANATION_NO_RUN_GUARDS,
    }
}

/// Serializes one diagnostic explanation as pretty JSON.
pub fn diagnostic_explanation_json_pretty(code: &str) -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(&diagnostic_explanation(code))
}

/// Serializes the compact diagnostic-code registry as pretty JSON.
pub fn diagnostic_code_registry_json_pretty() -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(DIAGNOSTIC_CODE_REGISTRY)
}

/// Serializes unsupported-feature diagnostic metadata as pretty JSON.
pub fn unsupported_feature_diagnostics_json_pretty() -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(UNSUPPORTED_FEATURE_DIAGNOSTICS)
}

/// Primary source span attached to a compiler diagnostic.
///
/// Text rendering uses one-based `line` and `column` plus an optional source
/// snippet. LSP rendering converts the same label to zero-based UTF-16 ranges.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct DiagnosticLabel {
    /// Source path displayed in diagnostics.
    #[serde(serialize_with = "serialize_path_display")]
    pub path: PathBuf,
    /// One-based source line.
    pub line: usize,
    /// One-based source column measured in scalar values for text rendering.
    pub column: usize,
    /// Label width in source characters; at least one.
    pub length: usize,
    /// Byte offset of the label start, when known.
    pub byte_start: Option<usize>,
    /// Byte offset of the label end, when known.
    pub byte_end: Option<usize>,
    /// Full source line used by the text renderer and UTF-16 range conversion.
    pub source_line: Option<String>,
    /// Label message shown beside the caret underline.
    pub message: String,
}

/// Zero-based LSP position measured with `LSP_POSITION_ENCODING`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct LspPosition {
    /// Zero-based line number.
    pub line: usize,
    /// Zero-based character offset in the negotiated encoding.
    pub character: usize,
}

/// LSP diagnostic range.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct LspRange {
    /// Inclusive start position.
    pub start: LspPosition,
    /// Exclusive end position.
    pub end: LspPosition,
}

/// LSP `Diagnostic`-shaped payload emitted by `--diagnostic-format lsp-json`.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct LspDiagnostic {
    /// Source range for the diagnostic.
    pub range: LspRange,
    /// Numeric LSP severity.
    pub severity: u8,
    /// Stable compiler diagnostic code.
    pub code: String,
    /// LSP diagnostic source.
    pub source: String,
    /// Human-readable diagnostic message.
    pub message: String,
    /// Versioned laniusc metadata carried in the LSP `data` field.
    pub data: LspDiagnosticData,
}

/// Versioned laniusc metadata embedded in an LSP diagnostic.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct LspDiagnosticData {
    /// Payload schema version.
    pub schema_version: u32,
    /// Payload schema name.
    pub schema_name: &'static str,
    /// Registry version used to interpret `code`.
    pub registry_schema_version: u32,
    /// Position encoding used by `range`.
    pub position_encoding: &'static str,
    /// Stable title for the diagnostic code.
    pub title: String,
    /// Stable category for the diagnostic code.
    pub category: String,
    /// Whether this diagnostic code normally carries a primary label.
    pub primary_label_policy: DiagnosticPrimaryLabelPolicy,
    /// CLI command that explains the diagnostic code.
    pub explain_command: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    /// Optional help text attached to the diagnostic.
    pub help: Option<String>,
    /// Additional notes attached to the diagnostic.
    pub notes: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    /// Source-label metadata, if the diagnostic has a primary label.
    pub primary_label: Option<LspDiagnosticPrimaryLabel>,
}

/// Source-label metadata carried in an LSP diagnostic's `data` field.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct LspDiagnosticPrimaryLabel {
    /// Display path for the source label.
    pub path: String,
    /// One-based source line from the original label.
    pub line: usize,
    /// One-based source column from the original label.
    pub column: usize,
    /// Label width in source characters.
    pub length: usize,
    /// Byte offset of the label start, when known.
    pub byte_start: Option<usize>,
    /// Byte offset of the label end, when known.
    pub byte_end: Option<usize>,
    /// Label message shown in text diagnostics.
    pub message: String,
}

impl DiagnosticLabel {
    /// Creates a primary diagnostic label using one-based text coordinates.
    pub fn primary(
        path: impl Into<PathBuf>,
        line: usize,
        column: usize,
        length: usize,
        source_line: Option<String>,
        message: impl Into<String>,
    ) -> Self {
        Self {
            path: path.into(),
            line,
            column,
            length,
            byte_start: None,
            byte_end: None,
            source_line,
            message: message.into(),
        }
        .normalized_public()
    }

    /// Attaches byte offsets to a label while preserving its text coordinates.
    pub fn with_byte_span(mut self, byte_start: usize, byte_end: usize) -> Self {
        self.byte_start = Some(byte_start);
        self.byte_end = Some(byte_end.max(byte_start));
        self
    }

    fn normalized_public(mut self) -> Self {
        self.line = self.line.max(1);
        self.column = self.column.max(1);
        self.length = self.length.max(1);
        if let Some(source_line) = self.source_line.as_deref() {
            let source_columns = source_line.chars().count();
            let max_column = source_columns.saturating_add(1).max(1);
            self.column = self.column.min(max_column);
            let max_length = max_column.saturating_sub(self.column).max(1);
            self.length = self.length.min(max_length);
        }
        self.message = public_required_text(self.message, DIAGNOSTIC_LABEL_MESSAGE_FALLBACK);
        if let (Some(byte_start), Some(byte_end)) = (self.byte_start, self.byte_end) {
            self.byte_end = Some(byte_end.max(byte_start));
        }
        self
    }
}

/// Converts a byte span in source text into a primary diagnostic label.
///
/// The span is snapped to UTF-8 character boundaries before line, column, and
/// length are computed. That lets compiler-produced byte positions still produce
/// stable diagnostics when they point into a multibyte character.
pub(in crate::compiler) fn diagnostic_label_from_source_span(
    path: impl Into<PathBuf>,
    source: &str,
    start: usize,
    len: usize,
    message: impl Into<String>,
) -> DiagnosticLabel {
    let source_len = source.len();
    let requested_start = start.min(source_len);
    let requested_end = requested_start.saturating_add(len).min(source_len);
    let span_start = floor_char_boundary(source, requested_start);
    let span_end = ceil_char_boundary(source, requested_end).max(span_start);
    let line_start = source[..span_start]
        .rfind('\n')
        .map(|index| index + 1)
        .unwrap_or(0);
    let line_end = trim_cr_before_newline(
        source,
        source[span_start..]
            .find('\n')
            .map(|index| span_start + index)
            .unwrap_or(source_len),
    );
    let line = source[..line_start]
        .bytes()
        .filter(|byte| *byte == b'\n')
        .count()
        + 1;
    let column = char_count_or_bytes(source, line_start, span_start) + 1;
    let length = char_count_or_bytes(source, span_start, span_end).max(1);
    let source_line = source
        .get(line_start..line_end)
        .map(|line| line.to_string());

    DiagnosticLabel::primary(path, line, column, length, source_line, message)
        .with_byte_span(span_start, span_end)
}

/// Builds the standard diagnostic for a filesystem input path that could not be
/// read or inspected.
pub(in crate::compiler) fn input_read_failed_error(
    path: &Path,
    operation: impl Into<String>,
    label_message: impl Into<String>,
    err: std::io::Error,
    help: impl Into<String>,
) -> super::CompileError {
    super::CompileError::Diagnostic(
        Diagnostic::error("LNC0040", "input read failed")
            .with_primary_label(DiagnosticLabel::primary(path, 1, 1, 1, None, label_message))
            .with_note(format!("operation: {}", operation.into()))
            .with_note(format!("input path: {}", path.display()))
            .with_note(format!("I/O error kind: {:?}", err.kind()))
            .with_note(format!("I/O error: {err}"))
            .with_help(help),
    )
}

/// Builds the standard diagnostic for a filesystem input path that exists but
/// cannot be used as the requested input kind.
pub(in crate::compiler) fn input_path_invalid_error(
    path: &Path,
    operation: impl Into<String>,
    label_message: impl Into<String>,
    reason: impl Into<String>,
    help: impl Into<String>,
) -> super::CompileError {
    super::CompileError::Diagnostic(
        Diagnostic::error("LNC0040", "input read failed")
            .with_primary_label(DiagnosticLabel::primary(path, 1, 1, 1, None, label_message))
            .with_note(format!("operation: {}", operation.into()))
            .with_note(format!("input path: {}", path.display()))
            .with_note(reason)
            .with_help(help),
    )
}

/// Builds the standard diagnostic for a source-pack operation invoked with a
/// target that the operation cannot execute.
pub(in crate::compiler) fn source_pack_target_invalid_error(
    operation: impl Into<String>,
    actual_target: impl Into<String>,
    expected_target: impl Into<String>,
) -> super::CompileError {
    super::CompileError::Diagnostic(
        Diagnostic::error("LNC0062", "source-pack target invalid")
            .with_note(format!("operation: {}", operation.into()))
            .with_note(format!("received target: {}", actual_target.into()))
            .with_note(format!("expected target: {}", expected_target.into()))
            .with_help(
                "choose a concrete artifact target such as wasm or x86_64 before executing source-pack descriptor work",
            ),
    )
}

fn floor_char_boundary(source: &str, mut index: usize) -> usize {
    index = index.min(source.len());
    while index > 0 && !source.is_char_boundary(index) {
        index -= 1;
    }
    index
}

fn ceil_char_boundary(source: &str, mut index: usize) -> usize {
    index = index.min(source.len());
    while index < source.len() && !source.is_char_boundary(index) {
        index += 1;
    }
    index
}

fn char_count_or_bytes(source: &str, start: usize, end: usize) -> usize {
    if source.is_char_boundary(start) && source.is_char_boundary(end) {
        source[start..end].chars().count()
    } else {
        end.saturating_sub(start)
    }
}

fn trim_cr_before_newline(source: &str, line_end: usize) -> usize {
    if line_end > 0 && source.as_bytes().get(line_end - 1) == Some(&b'\r') {
        line_end - 1
    } else {
        line_end
    }
}

/// Converts a parser rejection for one source file into a structured syntax error.
pub(in crate::compiler) fn parser_failure_to_compile_error_for_source(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_buffer: &wgpu::Buffer,
    source: &str,
    diagnostic_path: &Path,
    failure: &ParserFailure,
) -> super::CompileError {
    if let Some(diagnostic) = lexical_syntax_error_to_compile_error(diagnostic_path, source) {
        return diagnostic;
    }

    if let Some(diagnostic) = trait_parser_rejection_diagnostic(diagnostic_path, source) {
        return diagnostic;
    }

    if let Some(label) = source_context_syntax_label(source) {
        return syntax_error_to_compile_error_for_source_span_with_message(
            diagnostic_path,
            source,
            label.start,
            label.len,
            label.message,
        );
    }

    if let Some(label) = ll1_rejection_syntax_label_for_source(source, failure) {
        return syntax_error_to_compile_error_for_source_span_with_message(
            diagnostic_path,
            source,
            label.start,
            label.len,
            label.message,
        );
    }

    let label =
        match read_single_token_from_buffer(device, queue, token_buffer, failure.ll1().error_pos) {
            Ok(token) => {
                let previous_token = previous_source_token(source, &token).or_else(|| {
                    previous_diagnostic_token(device, queue, token_buffer, failure.ll1().error_pos)
                });
                let next_token = next_source_token(source, &token).or_else(|| {
                    next_diagnostic_token(device, queue, token_buffer, failure.ll1().error_pos)
                });
                let (label_token, label_message) = parser_rejection_label_target(
                    source,
                    &token,
                    previous_token.as_ref(),
                    next_token.as_ref(),
                );
                diagnostic_label_from_source_span(
                    diagnostic_path,
                    source,
                    label_token.start,
                    label_token.len,
                    label_message,
                )
            }
            Err(_) => diagnostic_label_from_source_span(
                diagnostic_path,
                source,
                fallback_syntax_error_start(source),
                1,
                "invalid syntax here",
            ),
        };

    super::CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error").with_primary_label(label),
    )
}

#[derive(Clone, Copy)]
enum TraitParserRejectionKind {
    Bound,
    Impl,
}

struct TraitParserRejection {
    kind: TraitParserRejectionKind,
    start: usize,
    len: usize,
}

fn trait_parser_rejection_diagnostic(
    diagnostic_path: &Path,
    source: &str,
) -> Option<super::CompileError> {
    let rejection = find_trait_parser_rejection(source)?;
    let label = match rejection.kind {
        TraitParserRejectionKind::Bound => "trait bound argument shape is not supported here",
        TraitParserRejectionKind::Impl => {
            "trait impl header uses an unsupported trait argument shape"
        }
    };
    let note = "use scalar, generic, or concrete non-nested trait arguments here; nested generic arguments are rejected rather than matching only the outer type name";

    let diagnostic = match rejection.kind {
        TraitParserRejectionKind::Bound => Diagnostic::error("LNC0008", "unsatisfied trait bound"),
        TraitParserRejectionKind::Impl => {
            Diagnostic::error("LNC0021", "invalid trait implementation")
        }
    };

    Some(super::CompileError::Diagnostic(
        diagnostic
            .with_primary_label(diagnostic_label_from_source_span(
                diagnostic_path,
                source,
                rejection.start,
                rejection.len,
                label,
            ))
            .with_note(note),
    ))
}

fn find_trait_parser_rejection(source: &str) -> Option<TraitParserRejection> {
    let mut line_start = 0usize;
    for line in source.split_inclusive('\n') {
        if let Some((start, len)) = unsupported_trait_impl_arg_span(line) {
            return Some(TraitParserRejection {
                kind: TraitParserRejectionKind::Impl,
                start: line_start + start,
                len,
            });
        }
        if let Some((start, len)) = unsupported_trait_bound_span(line) {
            return Some(TraitParserRejection {
                kind: TraitParserRejectionKind::Bound,
                start: line_start + start,
                len,
            });
        }
        line_start += line.len();
    }
    None
}

fn unsupported_trait_impl_arg_span(line: &str) -> Option<(usize, usize)> {
    let trimmed_start = line.len() - line.trim_start().len();
    let trimmed = &line[trimmed_start..];
    let after_impl = trimmed
        .strip_prefix("impl ")
        .map(|rest| (trimmed_start + "impl ".len(), rest))
        .or_else(|| {
            trimmed
                .strip_prefix("pub impl ")
                .map(|rest| (trimmed_start + "pub impl ".len(), rest))
        })?;

    let (mut head_start, mut rest) = after_impl;
    if rest.starts_with('<') {
        let skip = balanced_angle_prefix_len(rest)?;
        head_start += skip;
        rest = &rest[skip..];
        let whitespace = rest.len() - rest.trim_start().len();
        head_start += whitespace;
        rest = &rest[whitespace..];
    }

    let for_offset = rest.find(" for ")?;
    unsupported_trait_arg_span(&rest[..for_offset]).map(|(start, len)| (head_start + start, len))
}

fn unsupported_trait_bound_span(line: &str) -> Option<(usize, usize)> {
    let where_offset = line.find(" where ")? + " where ".len();
    let where_clause = &line[where_offset..];
    let colon_offset = where_clause.find(':')?;
    let bounds_start = where_offset + colon_offset + 1;
    let bounds = &line[bounds_start..];
    let leading_whitespace = bounds.len() - bounds.trim_start().len();
    let bounds = &bounds[leading_whitespace..];
    let bounds_start = bounds_start + leading_whitespace;

    if bounds.starts_with('&') {
        return Some((bounds_start, 1));
    }

    unsupported_trait_arg_span(bounds).map(|(start, len)| (bounds_start + start, len))
}

fn unsupported_trait_arg_span(text: &str) -> Option<(usize, usize)> {
    if let Some(offset) = text.find('&') {
        return Some((offset, 1));
    }

    let bytes = text.as_bytes();
    let mut depth = 0usize;
    let mut arg_start = None;
    for (index, byte) in bytes.iter().copied().enumerate() {
        match byte {
            b'<' => {
                if depth == 1 {
                    return Some((
                        arg_start.unwrap_or(index),
                        index - arg_start.unwrap_or(index),
                    ));
                }
                depth += 1;
                if depth == 1 {
                    arg_start = Some(index + 1);
                }
            }
            b'>' => {
                depth = depth.saturating_sub(1);
                if depth == 0 {
                    arg_start = None;
                }
            }
            b',' if depth == 1 => {
                arg_start = Some(index + 1 + following_whitespace_len(&text[index + 1..]));
            }
            _ => {}
        }
    }
    None
}

fn following_whitespace_len(text: &str) -> usize {
    text.len() - text.trim_start().len()
}

fn balanced_angle_prefix_len(text: &str) -> Option<usize> {
    let bytes = text.as_bytes();
    let mut depth = 0usize;
    for (index, byte) in bytes.iter().copied().enumerate() {
        match byte {
            b'<' => depth += 1,
            b'>' => {
                depth = depth.checked_sub(1)?;
                if depth == 0 {
                    return Some(index + 1);
                }
            }
            _ => {}
        }
    }
    None
}

/// Builds a structured syntax error for an already-known source span.
pub(in crate::compiler) fn syntax_error_to_compile_error_for_source_span(
    diagnostic_path: &Path,
    source: &str,
    start: usize,
    len: usize,
) -> super::CompileError {
    if let Some(label) = source_context_syntax_label(source) {
        return syntax_error_to_compile_error_for_source_span_with_message(
            diagnostic_path,
            source,
            label.start,
            label.len,
            label.message,
        );
    }

    let token = source_token_for_syntax_span(source, start, len);
    let previous_token = previous_source_token(source, &token);
    let next_token = next_source_token(source, &token);
    let (label_token, label_message) =
        parser_rejection_label_target(source, &token, previous_token.as_ref(), next_token.as_ref());
    syntax_error_to_compile_error_for_source_span_with_message(
        diagnostic_path,
        source,
        label_token.start,
        label_token.len,
        label_message,
    )
}

fn source_token_for_syntax_span(source: &str, start: usize, len: usize) -> Token {
    if let Some((token, _)) = source_token_at_or_after(source, start)
        && token.start == start
    {
        return token;
    }

    Token {
        kind: TokenKind::Ident,
        start,
        len,
    }
}

struct SourceSyntaxLabel {
    start: usize,
    len: usize,
    message: String,
}

struct SourceSyntaxTokens<'a> {
    source: &'a str,
    tokens: Vec<Token>,
}

impl<'a> SourceSyntaxTokens<'a> {
    fn from_source(source: &'a str) -> Self {
        let mut tokens = Vec::new();
        let mut index = 0usize;
        while let Some((token, next_index)) = source_token_at_or_after(source, index) {
            let next_index = next_index.max(token.start.saturating_add(token.len));
            tokens.push(token);
            index = next_index;
        }
        Self { source, tokens }
    }

    fn get(&self, index: usize) -> Option<&Token> {
        self.tokens.get(index)
    }

    fn eof_label(&self, message: impl Into<String>) -> SourceSyntaxLabel {
        SourceSyntaxLabel {
            start: self.source.len(),
            len: 1,
            message: message.into(),
        }
    }
}

type SourceSyntaxRule = for<'a> fn(&SourceSyntaxTokens<'a>) -> Option<SourceSyntaxLabel>;

const SOURCE_SYNTAX_RULES: &[SourceSyntaxRule] = &[
    missing_assignment_expression_label,
    missing_control_flow_block_label,
    missing_module_path_label,
    missing_statement_semicolon_label,
];

fn source_context_syntax_label(source: &str) -> Option<SourceSyntaxLabel> {
    let tokens = SourceSyntaxTokens::from_source(source);
    SOURCE_SYNTAX_RULES.iter().find_map(|rule| rule(&tokens))
}

fn ll1_rejection_syntax_label_for_source(
    source: &str,
    failure: &ParserFailure,
) -> Option<SourceSyntaxLabel> {
    let semantic_token_kinds = failure.semantic_token_kinds()?;
    let rejection = failure.ll1_rejection()?;
    let source_tokens = SourceSyntaxTokens::from_source(source);
    Some(source_tokens.label_for_ll1_rejection(semantic_token_kinds, rejection))
}

struct SourcePackSyntaxToken<'a> {
    file: &'a DiagnosticSourceFile,
    token: Token,
}

fn ll1_rejection_syntax_label_for_source_pack<'a>(
    files: &'a [DiagnosticSourceFile],
    failure: &ParserFailure,
) -> Option<(&'a DiagnosticSourceFile, SourceSyntaxLabel)> {
    let semantic_token_kinds = failure.semantic_token_kinds()?;
    let rejection = failure.ll1_rejection()?;
    let tokens = source_pack_syntax_tokens(files);
    let first_input = ll1_first_input_index(semantic_token_kinds);
    let source_index = rejection.pos.checked_sub(first_input);
    let message = ll1_rejection_message_for_context(
        tokens
            .get(source_index?)
            .map(|entry| syntax_token_description(&entry.file.source, &entry.token))
            .unwrap_or_else(|| "end of input".to_string()),
        rejection,
    );

    if let Some(entry) = tokens.get(source_index?) {
        return Some((
            entry.file,
            SourceSyntaxLabel {
                start: entry.token.start,
                len: entry.token.len,
                message,
            },
        ));
    }

    let file = files.last()?;
    Some((file, source_pack_eof_label(file, message)))
}

fn source_pack_syntax_tokens(files: &[DiagnosticSourceFile]) -> Vec<SourcePackSyntaxToken<'_>> {
    let mut tokens = Vec::new();
    for file in files {
        let source_tokens = SourceSyntaxTokens::from_source(&file.source);
        tokens.extend(
            source_tokens
                .tokens
                .into_iter()
                .map(|token| SourcePackSyntaxToken { file, token }),
        );
    }
    tokens
}

fn source_pack_eof_label(
    file: &DiagnosticSourceFile,
    message: impl Into<String>,
) -> SourceSyntaxLabel {
    SourceSyntaxLabel {
        start: file.source.len(),
        len: 1,
        message: message.into(),
    }
}

fn ll1_first_input_index(semantic_token_kinds: &[u32]) -> usize {
    if semantic_token_kinds.first().copied() == Some(0) {
        1
    } else {
        0
    }
}

impl SourceSyntaxTokens<'_> {
    fn label_for_ll1_rejection(
        &self,
        semantic_token_kinds: &[u32],
        rejection: &Ll1RejectionContext,
    ) -> SourceSyntaxLabel {
        let first_input = ll1_first_input_index(semantic_token_kinds);
        let source_index = rejection.pos.checked_sub(first_input);
        let found = source_index
            .and_then(|index| self.tokens.get(index))
            .map(|token| syntax_token_description(self.source, token))
            .unwrap_or_else(|| "end of input".to_string());
        let message = ll1_rejection_message_for_context(found, rejection);

        if let Some(token) = source_index.and_then(|index| self.tokens.get(index)) {
            SourceSyntaxLabel {
                start: token.start,
                len: token.len,
                message,
            }
        } else {
            self.eof_label(message)
        }
    }
}

fn ll1_rejection_message_for_context(found: String, rejection: &Ll1RejectionContext) -> String {
    match expected_syntax_terminal_list(&rejection.expected) {
        Some(expected) => format!("expected {expected}, found {found}"),
        None => format!("unexpected {found}"),
    }
}

fn expected_syntax_terminal_list(expected: &[u32]) -> Option<String> {
    let mut terminals = Vec::new();
    for &kind in expected {
        let description = expected_syntax_terminal_description(kind);
        if !terminals.contains(&description) {
            terminals.push(description);
        }
    }

    match terminals.len() {
        0 => None,
        1 => terminals.pop(),
        2 => Some(format!("{} or {}", terminals[0], terminals[1])),
        _ => {
            let last = terminals
                .pop()
                .expect("terminal list should have a last item");
            Some(format!("one of {}, or {last}", terminals.join(", ")))
        }
    }
}

fn expected_syntax_terminal_description(kind: u32) -> String {
    if kind == 0 {
        return "end of input".to_string();
    }

    let Some(kind) = TokenKind::from_u32(kind).map(canonical_expected_token_kind) else {
        return format!("token #{kind}");
    };

    match kind {
        TokenKind::Ident => "identifier".to_string(),
        TokenKind::Int => "integer literal".to_string(),
        TokenKind::Float => "float literal".to_string(),
        TokenKind::String => "string literal".to_string(),
        TokenKind::Char => "character literal".to_string(),
        kind if syntax_token_is_keyword(kind) => format!(
            "keyword `{}`",
            expected_keyword_text(kind).unwrap_or("keyword")
        ),
        kind => expected_punctuation_text(kind)
            .map(|text| format!("`{text}`"))
            .unwrap_or_else(|| format!("{kind:?}")),
    }
}

fn canonical_expected_token_kind(kind: TokenKind) -> TokenKind {
    match kind {
        TokenKind::LetIdent
        | TokenKind::ParamIdent
        | TokenKind::TypeIdent
        | TokenKind::MemberIdent
        | TokenKind::TypeAliasNameIdent
        | TokenKind::TraitNameIdent
        | TokenKind::GenericParamIdent
        | TokenKind::WhereIdent
        | TokenKind::BoundTypeIdent
        | TokenKind::RangeEndIdent
        | TokenKind::PathGenericIdent => TokenKind::Ident,
        TokenKind::CallLParen
        | TokenKind::GroupLParen
        | TokenKind::ParamLParen
        | TokenKind::PatternLParen
        | TokenKind::EnumPayloadLParen => TokenKind::LParen,
        TokenKind::CallRParen
        | TokenKind::GroupRParen
        | TokenKind::ParamRParen
        | TokenKind::PatternRParen
        | TokenKind::EnumPayloadRParen => TokenKind::RParen,
        TokenKind::IndexLBracket | TokenKind::ArrayLBracket | TokenKind::TypeArrayLBracket => {
            TokenKind::LBracket
        }
        TokenKind::IndexRBracket | TokenKind::ArrayRBracket | TokenKind::TypeArrayRBracket => {
            TokenKind::RBracket
        }
        TokenKind::IfLBrace
        | TokenKind::MatchLBrace
        | TokenKind::ImplLBrace
        | TokenKind::TraitLBrace
        | TokenKind::StructLitLBrace
        | TokenKind::StructDeclLBrace
        | TokenKind::EnumLBrace
        | TokenKind::FnBlockLBrace
        | TokenKind::ImplFnBlockLBrace => TokenKind::LBrace,
        TokenKind::IfRBrace
        | TokenKind::MatchRBrace
        | TokenKind::ImplRBrace
        | TokenKind::TraitRBrace
        | TokenKind::StructLitRBrace
        | TokenKind::StructDeclRBrace
        | TokenKind::EnumRBrace
        | TokenKind::FnBlockRBrace
        | TokenKind::ImplFnBlockRBrace => TokenKind::RBrace,
        TokenKind::LetAssign
        | TokenKind::DeclAssign
        | TokenKind::TypeAliasAssign
        | TokenKind::ConstAssign
        | TokenKind::RangeInclusiveAssign => TokenKind::Assign,
        TokenKind::TypeSemicolon
        | TokenKind::TraitMethodSemicolon
        | TokenKind::ImportSemicolon
        | TokenKind::ModuleSemicolon
        | TokenKind::ExternSemicolon
        | TokenKind::TypeAliasSemicolon
        | TokenKind::ConstSemicolon
        | TokenKind::LetSemicolon
        | TokenKind::ReturnSemicolon
        | TokenKind::ExprSemicolon
        | TokenKind::BreakSemicolon
        | TokenKind::ContinueSemicolon => TokenKind::Semicolon,
        TokenKind::ArgComma
        | TokenKind::ArrayComma
        | TokenKind::ParamComma
        | TokenKind::TypeArgComma
        | TokenKind::GenericParamComma
        | TokenKind::EnumFieldComma
        | TokenKind::MatchArmComma
        | TokenKind::PatternComma
        | TokenKind::WhereComma
        | TokenKind::EnumVariantComma
        | TokenKind::StructFieldComma
        | TokenKind::StructLitComma
        | TokenKind::BoundTypeArgComma
        | TokenKind::PathTypeArgComma => TokenKind::Comma,
        TokenKind::BoundColon | TokenKind::TypeColon | TokenKind::PathColon => TokenKind::Colon,
        TokenKind::TypeArgLt
        | TokenKind::GenericParamLt
        | TokenKind::BoundTypeArgLt
        | TokenKind::PathTypeArgLt => TokenKind::Lt,
        TokenKind::TypeArgGt
        | TokenKind::GenericParamGt
        | TokenKind::BoundTypeArgGt
        | TokenKind::PathTypeArgGt => TokenKind::Gt,
        TokenKind::TypeAmpersand | TokenKind::BoundTypeAmpersand => TokenKind::Ampersand,
        TokenKind::PrefixPlus | TokenKind::InfixPlus | TokenKind::BoundPlus => TokenKind::Plus,
        TokenKind::PrefixMinus | TokenKind::InfixMinus => TokenKind::Minus,
        TokenKind::ImplPub | TokenKind::TraitPub => TokenKind::Pub,
        TokenKind::ParamSelfValue | TokenKind::ParamSelfRefValue => TokenKind::SelfValue,
        kind => kind,
    }
}

fn expected_keyword_text(kind: TokenKind) -> Option<&'static str> {
    match kind {
        TokenKind::Pub => Some("pub"),
        TokenKind::Fn => Some("fn"),
        TokenKind::Let => Some("let"),
        TokenKind::Return => Some("return"),
        TokenKind::If => Some("if"),
        TokenKind::Else => Some("else"),
        TokenKind::While => Some("while"),
        TokenKind::Break => Some("break"),
        TokenKind::Continue => Some("continue"),
        TokenKind::True => Some("true"),
        TokenKind::False => Some("false"),
        TokenKind::Const => Some("const"),
        TokenKind::Enum => Some("enum"),
        TokenKind::Struct => Some("struct"),
        TokenKind::Match => Some("match"),
        TokenKind::Import => Some("import"),
        TokenKind::Module => Some("module"),
        TokenKind::Impl => Some("impl"),
        TokenKind::Trait => Some("trait"),
        TokenKind::For => Some("for"),
        TokenKind::In => Some("in"),
        TokenKind::Extern => Some("extern"),
        TokenKind::Type => Some("type"),
        TokenKind::Where => Some("where"),
        TokenKind::SelfValue => Some("self"),
        _ => None,
    }
}

fn expected_punctuation_text(kind: TokenKind) -> Option<&'static str> {
    match kind {
        TokenKind::LParen => Some("("),
        TokenKind::RParen => Some(")"),
        TokenKind::LBracket => Some("["),
        TokenKind::RBracket => Some("]"),
        TokenKind::LBrace => Some("{"),
        TokenKind::RBrace => Some("}"),
        TokenKind::Plus => Some("+"),
        TokenKind::Minus => Some("-"),
        TokenKind::Star => Some("*"),
        TokenKind::Slash => Some("/"),
        TokenKind::Percent => Some("%"),
        TokenKind::Assign => Some("="),
        TokenKind::EqEq => Some("=="),
        TokenKind::NotEqual => Some("!="),
        TokenKind::Lt => Some("<"),
        TokenKind::Gt => Some(">"),
        TokenKind::Le => Some("<="),
        TokenKind::Ge => Some(">="),
        TokenKind::AndAnd => Some("&&"),
        TokenKind::OrOr => Some("||"),
        TokenKind::Not => Some("!"),
        TokenKind::Ampersand => Some("&"),
        TokenKind::Pipe => Some("|"),
        TokenKind::Dot => Some("."),
        TokenKind::Comma => Some(","),
        TokenKind::Semicolon => Some(";"),
        TokenKind::Colon => Some(":"),
        TokenKind::Question => Some("?"),
        TokenKind::Arrow => Some("->"),
        TokenKind::MatchArrow => Some("=>"),
        TokenKind::DotDot => Some(".."),
        TokenKind::DotDotEqual => Some("..="),
        TokenKind::Shl => Some("<<"),
        TokenKind::Shr => Some(">>"),
        TokenKind::Tilde => Some("~"),
        TokenKind::Caret => Some("^"),
        TokenKind::PlusAssign => Some("+="),
        TokenKind::MinusAssign => Some("-="),
        TokenKind::StarAssign => Some("*="),
        TokenKind::SlashAssign => Some("/="),
        TokenKind::PercentAssign => Some("%="),
        TokenKind::CaretAssign => Some("^="),
        TokenKind::ShlAssign => Some("<<="),
        TokenKind::ShrAssign => Some(">>="),
        TokenKind::AmpAssign => Some("&="),
        TokenKind::PipeAssign => Some("|="),
        TokenKind::Inc | TokenKind::PrefixInc | TokenKind::PostfixInc => Some("++"),
        TokenKind::Dec | TokenKind::PrefixDec | TokenKind::PostfixDec => Some("--"),
        _ => None,
    }
}

fn missing_control_flow_block_label(tokens: &SourceSyntaxTokens<'_>) -> Option<SourceSyntaxLabel> {
    for (index, token) in tokens.tokens.iter().enumerate() {
        let Some(context) = control_flow_condition_context(token.kind) else {
            continue;
        };

        let Some(open_paren) = tokens.get(index + 1) else {
            continue;
        };
        if open_paren.kind != TokenKind::LParen {
            continue;
        }

        let mut paren_depth = 1u32;
        let mut cursor = index + 2;
        while let Some(scan_token) = tokens.get(cursor) {
            match scan_token.kind {
                TokenKind::LParen => paren_depth = paren_depth.saturating_add(1),
                TokenKind::RParen => {
                    paren_depth = paren_depth.saturating_sub(1);
                    if paren_depth == 0 {
                        match tokens.get(cursor + 1) {
                            Some(next_token) if next_token.kind != TokenKind::LBrace => {
                                return Some(SourceSyntaxLabel {
                                    start: next_token.start,
                                    len: next_token.len,
                                    message: format!(
                                        "expected `{{` after {context} condition, found {}",
                                        syntax_token_description(tokens.source, next_token)
                                    ),
                                });
                            }
                            None => {
                                return Some(tokens.eof_label(format!(
                                    "expected `{{` after {context} condition, found end of input"
                                )));
                            }
                            _ => break,
                        }
                    }
                }
                _ => {}
            }
            cursor += 1;
        }
    }
    None
}

fn control_flow_condition_context(kind: TokenKind) -> Option<&'static str> {
    match kind {
        TokenKind::If => Some("if"),
        TokenKind::While => Some("while"),
        _ => None,
    }
}

fn missing_assignment_expression_label(
    tokens: &SourceSyntaxTokens<'_>,
) -> Option<SourceSyntaxLabel> {
    for (index, token) in tokens.tokens.iter().enumerate() {
        if !token_starts_assignment_expression(token.kind) {
            continue;
        }

        match tokens.get(index + 1) {
            Some(next_token) if token_ends_missing_assignment_expression(next_token.kind) => {
                return Some(SourceSyntaxLabel {
                    start: next_token.start,
                    len: next_token.len,
                    message: "expected expression after `=`".to_string(),
                });
            }
            None => return Some(tokens.eof_label("expected expression after `=`")),
            _ => {}
        }
    }
    None
}

fn token_starts_assignment_expression(kind: TokenKind) -> bool {
    matches!(
        kind,
        TokenKind::Assign | TokenKind::LetAssign | TokenKind::DeclAssign | TokenKind::ConstAssign
    )
}

fn token_ends_missing_assignment_expression(kind: TokenKind) -> bool {
    token_terminates_statement(kind) || kind == TokenKind::RBrace
}

fn missing_module_path_label(tokens: &SourceSyntaxTokens<'_>) -> Option<SourceSyntaxLabel> {
    for (index, token) in tokens.tokens.iter().enumerate() {
        let Some(keyword) = module_path_declaration_keyword(token.kind) else {
            continue;
        };

        match tokens.get(index + 1) {
            Some(next_token) if token_ends_missing_module_path(next_token.kind) => {
                return Some(SourceSyntaxLabel {
                    start: next_token.start,
                    len: next_token.len,
                    message: format!("expected module path after `{keyword}`"),
                });
            }
            Some(next_token) if !token_can_start_module_path(next_token.kind) => {
                return Some(SourceSyntaxLabel {
                    start: next_token.start,
                    len: next_token.len,
                    message: format!(
                        "expected module path after `{keyword}`, found {}",
                        syntax_token_description(tokens.source, next_token)
                    ),
                });
            }
            None => {
                return Some(tokens.eof_label(format!(
                    "expected module path after `{keyword}`, found end of input"
                )));
            }
            _ => {}
        }
    }
    None
}

fn module_path_declaration_keyword(kind: TokenKind) -> Option<&'static str> {
    match kind {
        TokenKind::Import => Some("import"),
        TokenKind::Module => Some("module"),
        _ => None,
    }
}

fn token_ends_missing_module_path(kind: TokenKind) -> bool {
    token_terminates_statement(kind) || kind == TokenKind::RBrace
}

fn token_can_start_module_path(kind: TokenKind) -> bool {
    kind == TokenKind::Ident
}

fn missing_statement_semicolon_label(tokens: &SourceSyntaxTokens<'_>) -> Option<SourceSyntaxLabel> {
    for (index, token) in tokens.tokens.iter().enumerate() {
        let Some(statement_context) = semicolon_terminated_statement_context(token.kind) else {
            continue;
        };

        let mut expression_depth = 0u32;
        let mut cursor = index + 1;
        while let Some(scan_token) = tokens.get(cursor) {
            if expression_depth == 0 && token_terminates_statement(scan_token.kind) {
                break;
            }
            if expression_depth == 0 && scan_token.kind == TokenKind::RBrace {
                return Some(SourceSyntaxLabel {
                    start: scan_token.start,
                    len: scan_token.len,
                    message: format!("expected ';' after {statement_context}"),
                });
            }

            match scan_token.kind {
                TokenKind::LParen | TokenKind::LBracket | TokenKind::LBrace => {
                    expression_depth = expression_depth.saturating_add(1);
                }
                TokenKind::RParen | TokenKind::RBracket | TokenKind::RBrace => {
                    expression_depth = expression_depth.saturating_sub(1);
                }
                _ => {}
            }
            cursor += 1;
        }

        if cursor >= tokens.tokens.len() {
            return Some(tokens.eof_label(format!("expected ';' after {statement_context}")));
        }
    }
    None
}

fn semicolon_terminated_statement_context(kind: TokenKind) -> Option<&'static str> {
    match kind {
        TokenKind::Return => Some("return statement"),
        TokenKind::Break => Some("break statement"),
        TokenKind::Continue => Some("continue statement"),
        TokenKind::Let => Some("let statement"),
        _ => None,
    }
}

fn token_terminates_statement(kind: TokenKind) -> bool {
    matches!(
        kind,
        TokenKind::Semicolon
            | TokenKind::LetSemicolon
            | TokenKind::ReturnSemicolon
            | TokenKind::ExprSemicolon
            | TokenKind::BreakSemicolon
            | TokenKind::ContinueSemicolon
            | TokenKind::TraitMethodSemicolon
            | TokenKind::ImportSemicolon
            | TokenKind::ModuleSemicolon
            | TokenKind::ExternSemicolon
            | TokenKind::TypeAliasSemicolon
            | TokenKind::ConstSemicolon
    )
}

fn syntax_error_to_compile_error_for_source_span_with_message(
    diagnostic_path: &Path,
    source: &str,
    start: usize,
    len: usize,
    message: impl Into<String>,
) -> super::CompileError {
    super::CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error").with_primary_label(
            diagnostic_label_from_source_span(diagnostic_path, source, start, len, message),
        ),
    )
}

/// Source file plus global byte range used for source-pack diagnostics.
#[derive(Clone, Debug)]
pub(in crate::compiler) struct DiagnosticSourceFile {
    /// Display path for diagnostics.
    pub path: PathBuf,
    /// Source text for the file.
    pub source: String,
    /// Inclusive start offset in the concatenated source-pack stream.
    pub global_start: usize,
    /// Exclusive end offset in the concatenated source-pack stream.
    pub global_end: usize,
}

impl DiagnosticSourceFile {
    /// Converts a global source-pack byte offset into a file-local byte offset.
    pub(in crate::compiler) fn local_start_for_global(&self, global_start: usize) -> usize {
        global_start
            .saturating_sub(self.global_start)
            .min(self.source.len())
    }
}

/// Builds diagnostic source-file records for concatenated source-pack input.
pub(in crate::compiler) fn source_pack_diagnostic_files<S: AsRef<str>>(
    sources: &[S],
    source_paths: Option<&[Option<PathBuf>]>,
) -> Vec<DiagnosticSourceFile> {
    let mut global_start = 0usize;
    sources
        .iter()
        .enumerate()
        .map(|(source_i, source)| {
            let source = source.as_ref().to_string();
            let global_end = global_start.saturating_add(source.len());
            let path = source_paths
                .and_then(|paths| paths.get(source_i))
                .and_then(|path| path.clone())
                .unwrap_or_else(|| PathBuf::from(format!("<source pack file {source_i}>")));
            let file = DiagnosticSourceFile {
                path,
                source,
                global_start,
                global_end,
            };
            global_start = global_end;
            file
        })
        .collect()
}

/// Finds the source-pack file that owns a global byte offset.
pub(in crate::compiler) fn source_pack_file_for_global_span(
    files: &[DiagnosticSourceFile],
    global_start: usize,
) -> Option<&DiagnosticSourceFile> {
    files
        .iter()
        .find(|file| global_start >= file.global_start && global_start < file.global_end)
        .or_else(|| {
            files
                .iter()
                .find(|file| file.source.is_empty() && global_start == file.global_start)
        })
}

pub(in crate::compiler) fn source_pack_nearest_file_for_global_span(
    files: &[DiagnosticSourceFile],
    global_start: usize,
) -> Option<&DiagnosticSourceFile> {
    source_pack_file_for_global_span(files, global_start)
        .or_else(|| {
            files
                .iter()
                .rev()
                .find(|file| global_start >= file.global_start)
        })
        .or_else(|| files.first())
}

fn source_pack_fallback_syntax_error(
    file: &DiagnosticSourceFile,
    global_start: usize,
) -> super::CompileError {
    super::CompileError::Diagnostic(
        Diagnostic::error("LNC0016", "syntax error").with_primary_label(
            diagnostic_label_from_source_span(
                &file.path,
                &file.source,
                file.local_start_for_global(global_start),
                1,
                "invalid syntax here",
            ),
        ),
    )
}

/// Converts a parser rejection for source-pack input into a structured syntax error.
pub(in crate::compiler) fn parser_failure_to_compile_error_for_source_pack(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_buffer: &wgpu::Buffer,
    diagnostic_files: &[DiagnosticSourceFile],
    failure: &ParserFailure,
) -> super::CompileError {
    for file in diagnostic_files {
        if let Some(diagnostic) = lexical_syntax_error_to_compile_error(&file.path, &file.source) {
            return diagnostic;
        }
    }

    for file in diagnostic_files {
        if let Some(diagnostic) = trait_parser_rejection_diagnostic(&file.path, &file.source) {
            return diagnostic;
        }
    }

    for file in diagnostic_files {
        if let Some(label) = source_context_syntax_label(&file.source) {
            return syntax_error_to_compile_error_for_source_span_with_message(
                &file.path,
                &file.source,
                label.start,
                label.len,
                label.message,
            );
        }
    }

    if let Some((file, label)) =
        ll1_rejection_syntax_label_for_source_pack(diagnostic_files, failure)
    {
        return syntax_error_to_compile_error_for_source_span_with_message(
            &file.path,
            &file.source,
            label.start,
            label.len,
            label.message,
        );
    }

    match read_single_token_from_buffer(device, queue, token_buffer, failure.ll1().error_pos) {
        Ok(token) => {
            let Some(file) = source_pack_file_for_global_span(diagnostic_files, token.start) else {
                return source_pack_nearest_file_for_global_span(diagnostic_files, token.start)
                    .map(|fallback_file| {
                        source_pack_fallback_syntax_error(fallback_file, token.start)
                    })
                    .unwrap_or_else(|| {
                        super::CompileError::Diagnostic(Diagnostic::error(
                            "LNC0016",
                            "syntax error",
                        ))
                    });
            };
            let local_token = source_pack_local_token(&token, file);
            let previous_token = previous_source_token(&file.source, &local_token).or_else(|| {
                previous_diagnostic_token(device, queue, token_buffer, failure.ll1().error_pos)
                    .and_then(|previous| {
                        source_pack_file_for_global_span(diagnostic_files, previous.start)
                            .filter(|previous_file| std::ptr::eq(*previous_file, file))
                            .map(|_| source_pack_local_token(&previous, file))
                    })
            });
            let next_token = next_source_token(&file.source, &local_token).or_else(|| {
                next_diagnostic_token(device, queue, token_buffer, failure.ll1().error_pos)
                    .and_then(|next| {
                        source_pack_file_for_global_span(diagnostic_files, next.start)
                            .filter(|next_file| std::ptr::eq(*next_file, file))
                            .map(|_| source_pack_local_token(&next, file))
                    })
            });
            let (label_token, label_message) = parser_rejection_label_target(
                &file.source,
                &local_token,
                previous_token.as_ref(),
                next_token.as_ref(),
            );
            syntax_error_to_compile_error_for_source_span_with_message(
                &file.path,
                &file.source,
                label_token.start,
                label_token.len,
                label_message,
            )
        }
        Err(_read_err) => {
            let Some(file) = diagnostic_files.first() else {
                return super::CompileError::Diagnostic(Diagnostic::error(
                    "LNC0016",
                    "syntax error",
                ));
            };
            source_pack_fallback_syntax_error(
                file,
                file.global_start
                    .saturating_add(fallback_syntax_error_start(&file.source)),
            )
        }
    }
}

fn previous_diagnostic_token(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_buffer: &wgpu::Buffer,
    token_index: u32,
) -> Option<Token> {
    let previous_index = token_index.checked_sub(1)?;
    read_single_token_from_buffer(device, queue, token_buffer, previous_index).ok()
}

fn next_diagnostic_token(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_buffer: &wgpu::Buffer,
    token_index: u32,
) -> Option<Token> {
    let next_index = token_index.checked_add(1)?;
    read_single_token_from_buffer(device, queue, token_buffer, next_index).ok()
}

fn source_pack_local_token(token: &Token, file: &DiagnosticSourceFile) -> Token {
    Token {
        kind: token.kind,
        start: file.local_start_for_global(token.start),
        len: token.len,
    }
}

fn previous_source_token(source: &str, token: &Token) -> Option<Token> {
    let mut index = 0usize;
    let mut previous = None;
    while index < token.start {
        let (candidate, next_index) = source_token_at_or_after(source, index)?;
        if candidate.start >= token.start {
            break;
        }
        let next_index = next_index.max(candidate.start.saturating_add(candidate.len));
        previous = Some(candidate);
        index = next_index;
    }
    previous
}

fn next_source_token(source: &str, token: &Token) -> Option<Token> {
    let start = token.start.checked_add(token.len)?;
    let (token, _) = source_token_at_or_after(source, start)?;
    Some(token)
}

fn source_token_at_or_after(source: &str, start: usize) -> Option<(Token, usize)> {
    let bytes = source.as_bytes();
    let mut index = skip_source_trivia(bytes, start.min(bytes.len()));
    if index >= bytes.len() {
        return None;
    }

    let token_start = index;
    let byte = bytes[index];
    if byte.is_ascii_alphabetic() || byte == b'_' {
        index += 1;
        while index < bytes.len() && is_ascii_ident_continue(bytes[index]) {
            index += 1;
        }
        let text = source.get(token_start..index)?;
        return Some((
            Token {
                kind: source_identifier_token_kind(text),
                start: token_start,
                len: index - token_start,
            },
            index,
        ));
    }

    if byte.is_ascii_digit() {
        index = skip_number_like_token(bytes, index);
        let kind = if source
            .get(token_start..index)
            .is_some_and(|text| text.contains('.'))
        {
            TokenKind::Float
        } else {
            TokenKind::Int
        };
        return Some((
            Token {
                kind,
                start: token_start,
                len: index - token_start,
            },
            index,
        ));
    }

    if byte == b'"' {
        let end = skip_quoted_token(bytes, index, b'"').unwrap_or(index + 1);
        return Some((
            Token {
                kind: TokenKind::String,
                start: token_start,
                len: end - token_start,
            },
            end,
        ));
    }

    if byte == b'\'' {
        let end = skip_quoted_token(bytes, index, b'\'').unwrap_or(index + 1);
        return Some((
            Token {
                kind: TokenKind::Char,
                start: token_start,
                len: end - token_start,
            },
            end,
        ));
    }

    let (kind, len) = source_punctuation_token_kind(bytes, index)?;
    Some((
        Token {
            kind,
            start: token_start,
            len,
        },
        token_start + len,
    ))
}

fn skip_source_trivia(bytes: &[u8], mut index: usize) -> usize {
    loop {
        while index < bytes.len() && bytes[index].is_ascii_whitespace() {
            index += 1;
        }

        if bytes.get(index) == Some(&b'/') && bytes.get(index + 1) == Some(&b'/') {
            index += 2;
            while index < bytes.len() && bytes[index] != b'\n' {
                index += 1;
            }
            continue;
        }

        if bytes.get(index) == Some(&b'/') && bytes.get(index + 1) == Some(&b'*') {
            index += 2;
            let mut closed = false;
            while index + 1 < bytes.len() {
                if bytes[index] == b'*' && bytes[index + 1] == b'/' {
                    index += 2;
                    closed = true;
                    break;
                }
                index += 1;
            }
            if !closed {
                return bytes.len();
            }
            continue;
        }

        return index;
    }
}

fn source_identifier_token_kind(text: &str) -> TokenKind {
    match text {
        "pub" => TokenKind::Pub,
        "fn" => TokenKind::Fn,
        "let" => TokenKind::Let,
        "return" => TokenKind::Return,
        "if" => TokenKind::If,
        "else" => TokenKind::Else,
        "while" => TokenKind::While,
        "break" => TokenKind::Break,
        "continue" => TokenKind::Continue,
        "true" => TokenKind::True,
        "false" => TokenKind::False,
        "const" => TokenKind::Const,
        "enum" => TokenKind::Enum,
        "struct" => TokenKind::Struct,
        "match" => TokenKind::Match,
        "import" => TokenKind::Import,
        "module" => TokenKind::Module,
        "impl" => TokenKind::Impl,
        "trait" => TokenKind::Trait,
        "for" => TokenKind::For,
        "in" => TokenKind::In,
        "extern" => TokenKind::Extern,
        "type" => TokenKind::Type,
        "where" => TokenKind::Where,
        "self" => TokenKind::SelfValue,
        _ => TokenKind::Ident,
    }
}

fn source_punctuation_token_kind(bytes: &[u8], index: usize) -> Option<(TokenKind, usize)> {
    match bytes.get(index..index.saturating_add(2)) {
        Some(b"->") => return Some((TokenKind::Arrow, 2)),
        Some(b"==") => return Some((TokenKind::EqEq, 2)),
        Some(b"!=") => return Some((TokenKind::NotEqual, 2)),
        Some(b"<=") => return Some((TokenKind::Le, 2)),
        Some(b">=") => return Some((TokenKind::Ge, 2)),
        Some(b"&&") => return Some((TokenKind::AndAnd, 2)),
        Some(b"||") => return Some((TokenKind::OrOr, 2)),
        Some(b"<<") => return Some((TokenKind::Shl, 2)),
        Some(b">>") => return Some((TokenKind::Shr, 2)),
        Some(b"+=") => return Some((TokenKind::PlusAssign, 2)),
        Some(b"-=") => return Some((TokenKind::MinusAssign, 2)),
        Some(b"*=") => return Some((TokenKind::StarAssign, 2)),
        Some(b"/=") => return Some((TokenKind::SlashAssign, 2)),
        Some(b"%=") => return Some((TokenKind::PercentAssign, 2)),
        Some(b"^=") => return Some((TokenKind::CaretAssign, 2)),
        Some(b"&=") => return Some((TokenKind::AmpAssign, 2)),
        Some(b"|=") => return Some((TokenKind::PipeAssign, 2)),
        Some(b"++") => return Some((TokenKind::Inc, 2)),
        Some(b"--") => return Some((TokenKind::Dec, 2)),
        Some(b"..") => return Some((TokenKind::DotDot, 2)),
        _ => {}
    }

    let kind = match bytes.get(index).copied()? {
        b'(' => TokenKind::LParen,
        b')' => TokenKind::RParen,
        b'[' => TokenKind::LBracket,
        b']' => TokenKind::RBracket,
        b'{' => TokenKind::LBrace,
        b'}' => TokenKind::RBrace,
        b'+' => TokenKind::Plus,
        b'-' => TokenKind::Minus,
        b'*' => TokenKind::Star,
        b'/' => TokenKind::Slash,
        b'%' => TokenKind::Percent,
        b'=' => TokenKind::Assign,
        b'!' => TokenKind::Not,
        b'<' => TokenKind::Lt,
        b'>' => TokenKind::Gt,
        b'&' => TokenKind::Ampersand,
        b'|' => TokenKind::Pipe,
        b'.' => TokenKind::Dot,
        b',' => TokenKind::Comma,
        b';' => TokenKind::Semicolon,
        b':' => TokenKind::Colon,
        b'?' => TokenKind::Question,
        b'^' => TokenKind::Caret,
        b'~' => TokenKind::Tilde,
        b'"' => TokenKind::String,
        b'\'' => TokenKind::Char,
        _ => return None,
    };
    Some((kind, 1))
}

fn parser_rejection_label_target<'a>(
    source: &str,
    token: &'a Token,
    previous_token: Option<&'a Token>,
    next_token: Option<&'a Token>,
) -> (&'a Token, String) {
    if previous_token.is_some_and(|previous| token_source_text(source, previous) == Some("fn")) {
        return (
            token,
            format!(
                "expected function name, found {}",
                syntax_token_description(source, token)
            ),
        );
    }

    if token_source_text(source, token) == Some("fn")
        && let Some(next_token) = next_token
        && token_source_text(source, next_token) == Some("fn")
    {
        return (
            next_token,
            format!(
                "expected function name, found {}",
                syntax_token_description(source, next_token)
            ),
        );
    }

    (token, "invalid syntax here".to_string())
}

fn syntax_token_description(source: &str, token: &Token) -> String {
    let Some(text) = token_source_text(source, token) else {
        if token.start >= source.len() {
            return "end of input".to_string();
        }
        return format!("{:?}", token.kind);
    };

    if syntax_token_is_keyword(token.kind) {
        format!("keyword `{text}`")
    } else {
        format!("`{text}`")
    }
}

fn token_source_text<'a>(source: &'a str, token: &Token) -> Option<&'a str> {
    let end = token.start.checked_add(token.len)?;
    source.get(token.start..end).filter(|text| !text.is_empty())
}

fn syntax_token_is_keyword(kind: TokenKind) -> bool {
    matches!(
        kind,
        TokenKind::Pub
            | TokenKind::Fn
            | TokenKind::Let
            | TokenKind::Return
            | TokenKind::If
            | TokenKind::Else
            | TokenKind::While
            | TokenKind::Break
            | TokenKind::Continue
            | TokenKind::True
            | TokenKind::False
            | TokenKind::Const
            | TokenKind::Enum
            | TokenKind::Struct
            | TokenKind::Match
            | TokenKind::Import
            | TokenKind::Module
            | TokenKind::Impl
            | TokenKind::Trait
            | TokenKind::For
            | TokenKind::In
            | TokenKind::Extern
            | TokenKind::Type
            | TokenKind::Where
            | TokenKind::SelfValue
    )
}

/// Reads one GPU token record back to host memory for diagnostic mapping.
pub(in crate::compiler) fn read_single_token_from_buffer(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_buffer: &wgpu::Buffer,
    token_index: u32,
) -> Result<Token, String> {
    let token_stride = std::mem::size_of::<GpuToken>() as u64;
    let token_offset = u64::from(token_index)
        .checked_mul(token_stride)
        .ok_or_else(|| format!("token {token_index} byte offset overflow"))?;
    let token_end = token_offset
        .checked_add(token_stride)
        .ok_or_else(|| format!("token {token_index} byte end overflow"))?;
    if token_end > token_buffer.size() {
        return Err(format!(
            "token {token_index} byte range {token_offset}..{token_end} exceeds token buffer size {}",
            token_buffer.size()
        ));
    }

    let token_readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb.compiler.syntax.diagnostic_token"),
        size: token_stride,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("compiler.syntax.diagnostic-token-readback.encoder"),
    });
    encoder.copy_buffer_to_buffer(token_buffer, token_offset, &token_readback, 0, token_stride);
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "compiler.syntax.diagnostic-token-readback",
        encoder.finish(),
    );

    let token_slice = token_readback.slice(0..token_stride);
    crate::gpu::passes_core::map_readback_blocking(
        device,
        &token_slice,
        "compiler.syntax.diagnostic-token",
    )
    .map_err(|err| err.to_string())?;
    let mapped = token_slice.get_mapped_range();
    let mut tokens = read_tokens_from_mapped(&mapped, 1)?;
    drop(mapped);
    token_readback.unmap();
    tokens
        .pop()
        .ok_or_else(|| format!("token {token_index} readback returned no rows"))
}

fn fallback_syntax_error_start(source: &str) -> usize {
    source
        .char_indices()
        .last()
        .map(|(index, _)| index)
        .unwrap_or(0)
}

struct LexicalSyntaxError {
    start: usize,
    len: usize,
    message: String,
}

fn lexical_syntax_error_to_compile_error(
    diagnostic_path: &Path,
    source: &str,
) -> Option<super::CompileError> {
    let error = first_lexical_syntax_error(source)?;
    Some(super::CompileError::Diagnostic(
        Diagnostic::error("LNC0016", error.message.clone()).with_primary_label(
            diagnostic_label_from_source_span(
                diagnostic_path,
                source,
                error.start,
                error.len,
                error.message,
            ),
        ),
    ))
}

fn first_lexical_syntax_error(source: &str) -> Option<LexicalSyntaxError> {
    let bytes = source.as_bytes();
    let mut index = 0usize;
    while index < bytes.len() {
        let byte = bytes[index];
        match byte {
            b' ' | b'\t' | b'\n' | b'\r' => {
                index += 1;
            }
            b'a'..=b'z' | b'A'..=b'Z' | b'_' => {
                index += 1;
                while index < bytes.len() && is_ascii_ident_continue(bytes[index]) {
                    index += 1;
                }
            }
            b'0'..=b'9' => {
                index = skip_number_like_token(bytes, index);
            }
            b'/' if bytes.get(index + 1) == Some(&b'/') => {
                index += 2;
                while index < bytes.len() && bytes[index] != b'\n' {
                    index += 1;
                }
            }
            b'/' if bytes.get(index + 1) == Some(&b'*') => {
                let comment_start = index;
                index += 2;
                let mut closed = false;
                while index + 1 < bytes.len() {
                    if bytes[index] == b'*' && bytes[index + 1] == b'/' {
                        index += 2;
                        closed = true;
                        break;
                    }
                    index += 1;
                }
                if !closed {
                    return Some(LexicalSyntaxError {
                        start: comment_start,
                        len: 2,
                        message: "unterminated block comment".to_string(),
                    });
                }
            }
            b'"' => match skip_quoted_token(bytes, index, b'"') {
                Some(next) => index = next,
                None => {
                    return Some(LexicalSyntaxError {
                        start: index,
                        len: 1,
                        message: "unterminated string literal".to_string(),
                    });
                }
            },
            b'\'' => match skip_quoted_token(bytes, index, b'\'') {
                Some(next) => index = next,
                None => {
                    return Some(LexicalSyntaxError {
                        start: index,
                        len: 1,
                        message: "unterminated character literal".to_string(),
                    });
                }
            },
            b'(' | b')' | b'[' | b']' | b'{' | b'}' | b'+' | b'-' | b'*' | b'/' | b'%' | b'='
            | b'!' | b'<' | b'>' | b'&' | b'|' | b'.' | b',' | b';' | b':' | b'?' | b'^' | b'~' => {
                index += 1;
            }
            _ => {
                let ch = source[index..].chars().next()?;
                return Some(LexicalSyntaxError {
                    start: index,
                    len: ch.len_utf8(),
                    message: format!("unknown start of token: `{}`", display_unknown_token(ch)),
                });
            }
        }
    }
    None
}

fn is_ascii_ident_continue(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'_'
}

fn skip_number_like_token(bytes: &[u8], mut index: usize) -> usize {
    index += 1;
    while index < bytes.len() {
        match bytes[index] {
            b'0'..=b'9' | b'a'..=b'z' | b'A'..=b'Z' | b'_' => index += 1,
            b'.' if bytes.get(index + 1).is_some_and(u8::is_ascii_digit) => index += 1,
            _ => break,
        }
    }
    index
}

fn skip_quoted_token(bytes: &[u8], quote_start: usize, quote: u8) -> Option<usize> {
    let mut index = quote_start + 1;
    while index < bytes.len() {
        match bytes[index] {
            b'\\' => {
                index = index.saturating_add(2);
            }
            b'\n' | b'\r' => return None,
            byte if byte == quote => return Some(index + 1),
            _ => index += 1,
        }
    }
    None
}

fn display_unknown_token(ch: char) -> String {
    ch.escape_default().collect()
}

/// Structured compiler diagnostic used by CLI, JSON, and LSP renderers.
///
/// A `Diagnostic` is the user-facing error object carried by `CompileError`.
/// It stores stable registry metadata alongside the concrete message and source
/// label so all renderers are projections of the same object.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Diagnostic {
    /// Rendered diagnostic JSON schema version.
    pub schema_version: u32,
    /// Rendered diagnostic JSON schema name.
    pub schema_name: &'static str,
    /// Diagnostic registry version used to interpret `code`.
    pub registry_schema_version: u32,
    /// Diagnostic severity.
    pub severity: DiagnosticSeverity,
    /// Stable compiler diagnostic code.
    pub code: String,
    /// Stable registry title for `code`.
    pub title: String,
    /// Stable registry category for `code`.
    pub category: String,
    /// Whether this code normally carries a primary source label.
    pub primary_label_policy: DiagnosticPrimaryLabelPolicy,
    /// CLI command that explains this diagnostic code.
    pub explain_command: String,
    /// Concrete diagnostic message for this occurrence.
    pub message: String,
    /// Primary source label for this occurrence, when available.
    pub primary_label: Option<DiagnosticLabel>,
    #[serde(skip_serializing_if = "Option::is_none")]
    /// Optional help text shown after the primary label.
    pub help: Option<String>,
    /// Additional diagnostic notes.
    pub notes: Vec<String>,
}

impl Diagnostic {
    /// Creates an error diagnostic from a stable diagnostic code and message.
    ///
    /// The code is canonicalized from public selector forms. Debug builds assert
    /// that the code is registered so new diagnostics cannot silently skip the
    /// public registry.
    pub fn error(code: impl Into<String>, message: impl Into<String>) -> Self {
        let code = code.into();
        let code = canonical_diagnostic_code(&code);
        let code_info = diagnostic_code_info(&code);
        debug_assert!(
            code_info.is_some(),
            "diagnostic code {code} is not registered"
        );
        let (title, category) = code_info
            .map(|info| (info.title, info.category))
            .unwrap_or(("unregistered diagnostic", "unregistered"));
        let message = public_required_text(message, title);
        let primary_label_policy = code_info
            .map(|info| info.primary_label_policy)
            .unwrap_or(DiagnosticPrimaryLabelPolicy::None);
        let help = unsupported_feature_diagnostic_info(&code)
            .and_then(|diagnostic| non_empty_public_text(diagnostic.next_step));
        let explain_command = diagnostic_explain_command(&code);
        Self {
            schema_version: DIAGNOSTIC_JSON_SCHEMA_VERSION,
            schema_name: DIAGNOSTIC_JSON_SCHEMA_NAME,
            registry_schema_version: DIAGNOSTIC_REGISTRY_SCHEMA_VERSION,
            severity: DiagnosticSeverity::Error,
            code,
            title: title.to_string(),
            category: category.to_string(),
            primary_label_policy,
            explain_command,
            message,
            primary_label: None,
            help,
            notes: Vec::new(),
        }
    }

    /// Attaches the primary source label.
    pub fn with_primary_label(mut self, label: DiagnosticLabel) -> Self {
        self.primary_label = Some(label.normalized_public());
        self
    }

    /// Appends a nonempty note.
    pub fn with_note(mut self, note: impl Into<String>) -> Self {
        if let Some(note) = non_empty_public_text(note) {
            if !self.notes.iter().any(|existing| existing == &note) {
                self.notes.push(note);
            }
        }
        self
    }

    /// Replaces the diagnostic help text with a nonempty public string.
    pub fn with_help(mut self, help: impl Into<String>) -> Self {
        self.help = non_empty_public_text(help);
        self
    }

    /// Renders the diagnostic as the default human-readable text format.
    pub fn render(&self) -> String {
        let mut rendered = format!(
            "{}[{}]: {}",
            self.severity.as_str(),
            self.code,
            self.message
        );

        if let Some(label) = &self.primary_label {
            rendered.push('\n');
            rendered.push_str(&format!(
                " --> {}:{}:{}",
                label.path.display(),
                label.line,
                label.column
            ));
            if let Some(source_line) = &label.source_line {
                let width = label.line.to_string().len();
                rendered.push('\n');
                rendered.push_str(&format!("{:>width$} |\n", "", width = width));
                rendered.push_str(&format!(
                    "{:>width$} | {}\n",
                    label.line,
                    source_line,
                    width = width
                ));
                let caret_padding = " ".repeat(label.column.saturating_sub(1));
                let carets = "^".repeat(label.length.max(1));
                rendered.push_str(&format!(
                    "{:>width$} | {}{} {}",
                    "",
                    caret_padding,
                    carets,
                    label.message,
                    width = width
                ));
            } else {
                rendered.push('\n');
                rendered.push_str(&format!("     = {}", label.message));
            }
        }

        if let Some(help) = &self.help {
            rendered.push('\n');
            rendered.push_str(&format!("     = help: {help}"));
        }

        for note in self.public_notes() {
            rendered.push('\n');
            rendered.push_str(&format!("     = note: {note}"));
        }

        rendered
    }

    /// Renders the structured diagnostic JSON payload.
    pub fn render_json_pretty(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(&self.public_projection())
    }

    /// Converts this diagnostic to an LSP `Diagnostic`-shaped payload.
    ///
    /// Source ranges are zero-based and encoded with `LSP_POSITION_ENCODING`.
    /// Additional laniusc metadata is preserved under the LSP `data` field.
    pub fn to_lsp_diagnostic(&self) -> LspDiagnostic {
        let code_info = diagnostic_code_info(&self.code);
        let (severity, source, title, category, primary_label_policy): (
            u8,
            &str,
            &str,
            &str,
            DiagnosticPrimaryLabelPolicy,
        ) = if let Some(info) = code_info {
            (
                info.lsp_severity,
                info.lsp_source,
                info.title,
                info.category,
                info.primary_label_policy,
            )
        } else {
            (
                LSP_DIAGNOSTIC_ERROR_SEVERITY,
                LSP_DIAGNOSTIC_SOURCE,
                self.title.as_str(),
                self.category.as_str(),
                if self.primary_label.is_some() {
                    DiagnosticPrimaryLabelPolicy::Required
                } else {
                    DiagnosticPrimaryLabelPolicy::None
                },
            )
        };
        LspDiagnostic {
            range: self
                .primary_label
                .as_ref()
                .map(lsp_range_from_label)
                .unwrap_or_else(empty_lsp_range),
            severity,
            code: self.code.clone(),
            source: source.to_string(),
            message: self.message.clone(),
            data: LspDiagnosticData {
                schema_version: LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION,
                schema_name: LSP_DIAGNOSTIC_DATA_SCHEMA_NAME,
                registry_schema_version: DIAGNOSTIC_REGISTRY_SCHEMA_VERSION,
                position_encoding: LSP_POSITION_ENCODING,
                title: title.to_string(),
                category: category.to_string(),
                primary_label_policy,
                explain_command: diagnostic_explain_command(&self.code),
                help: self.help.clone(),
                notes: self.public_notes(),
                primary_label: self.primary_label.as_ref().map(lsp_primary_label_data),
            },
        }
    }

    /// Renders the LSP diagnostic payload as pretty JSON.
    pub fn render_lsp_json_pretty(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(&self.to_lsp_diagnostic())
    }

    fn public_projection(&self) -> Self {
        let mut diagnostic = self.clone();
        diagnostic.notes = self.public_notes();
        diagnostic
    }

    fn public_notes(&self) -> Vec<String> {
        let mut notes = self.notes.clone();
        if self.primary_label_policy == DiagnosticPrimaryLabelPolicy::Required
            && self.primary_label.is_none()
            && !notes
                .iter()
                .any(|note| note == MISSING_REQUIRED_PRIMARY_LABEL_NOTE)
        {
            notes.push(MISSING_REQUIRED_PRIMARY_LABEL_NOTE.to_string());
        }
        notes
    }
}

fn non_empty_public_text(text: impl Into<String>) -> Option<String> {
    let text = text.into();
    let text = normalize_public_text(&text);
    (!text.is_empty()).then_some(text)
}

fn normalize_public_text(text: &str) -> String {
    let text = text
        .chars()
        .map(|ch| if ch.is_control() { ' ' } else { ch })
        .collect::<String>();
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn public_required_text(text: impl Into<String>, fallback: &str) -> String {
    non_empty_public_text(text).unwrap_or_else(|| fallback.to_string())
}

const DIAGNOSTIC_LABEL_MESSAGE_FALLBACK: &str = "relevant source location";
const MISSING_REQUIRED_PRIMARY_LABEL_NOTE: &str = "source location unavailable for this diagnostic";

fn serialize_path_display<S>(path: &Path, serializer: S) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    serializer.serialize_str(&path.display().to_string())
}

/// Builds the public CLI command that explains a diagnostic code selector.
pub fn diagnostic_explain_command(code: &str) -> String {
    format!(
        "laniusc diagnostics explain {}",
        canonical_diagnostic_code(code)
    )
}

impl fmt::Display for Diagnostic {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.render())
    }
}

fn empty_lsp_range() -> LspRange {
    LspRange {
        start: LspPosition {
            line: 0,
            character: 0,
        },
        end: LspPosition {
            line: 0,
            character: 0,
        },
    }
}

fn lsp_primary_label_data(label: &DiagnosticLabel) -> LspDiagnosticPrimaryLabel {
    LspDiagnosticPrimaryLabel {
        path: label.path.display().to_string(),
        line: label.line,
        column: label.column,
        length: label.length,
        byte_start: label.byte_start,
        byte_end: label.byte_end,
        message: label.message.clone(),
    }
}

fn lsp_range_from_label(label: &DiagnosticLabel) -> LspRange {
    let line = label.line.saturating_sub(1);
    let start_char = label.column.saturating_sub(1);
    let end_char = start_char.saturating_add(label.length.max(1));
    let (start, end) = match label.source_line.as_deref() {
        Some(source_line) => (
            utf16_units_before_char(source_line, start_char),
            utf16_units_before_char(source_line, end_char),
        ),
        None => (start_char, end_char),
    };
    LspRange {
        start: LspPosition {
            line,
            character: start,
        },
        end: LspPosition {
            line,
            character: end.max(start),
        },
    }
}

fn utf16_units_before_char(source_line: &str, char_count: usize) -> usize {
    source_line
        .chars()
        .take(char_count)
        .map(char::len_utf16)
        .sum()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::tables::PrecomputedParseTables;

    fn api_info_has_expected_status(api: &RuntimeBoundApiDiagnosticInfo) -> bool {
        let expected_extern_abi = if api.api_name == "std::io::print_i32" {
            Some("compiler_print_i32")
        } else if api.api_name == "alloc::allocator::alloc" {
            Some("lanius_alloc")
        } else if api.api_name == "alloc::allocator::dealloc" {
            Some("lanius_alloc")
        } else if api.api_name == "std::random::secure_u32" {
            Some("lanius_std")
        } else if api.api_name == "std::process::exit" {
            Some("lanius_std")
        } else if api.api_name == "std::process::argc" {
            Some("lanius_std")
        } else if api.api_name == "std::process::arg_len" {
            Some("lanius_std")
        } else if api.api_name == "std::process::arg_read" {
            Some("lanius_std")
        } else if api.api_name == "std::io::write_stdout" {
            Some("compiler_host_stdio")
        } else if api.api_name == "std::io::write_stderr" {
            Some("compiler_host_stdio")
        } else if api.api_name == "std::io::read_stdin" {
            Some("compiler_host_stdio")
        } else {
            None
        };
        if let Some(extern_abi) = expected_extern_abi {
            return api.extern_abi == extern_abi
                && api.current_status == "executable-compiler-primitive"
                && api.executable;
        }
        api.current_status == "known-unbound" && !api.executable
    }

    fn api_json_has_expected_status(api: &serde_json::Value) -> bool {
        let expected_extern_abi = if api["api_name"] == "std::io::print_i32" {
            Some("compiler_print_i32")
        } else if api["api_name"] == "alloc::allocator::alloc" {
            Some("lanius_alloc")
        } else if api["api_name"] == "alloc::allocator::dealloc" {
            Some("lanius_alloc")
        } else if api["api_name"] == "std::random::secure_u32" {
            Some("lanius_std")
        } else if api["api_name"] == "std::process::exit" {
            Some("lanius_std")
        } else if api["api_name"] == "std::process::argc" {
            Some("lanius_std")
        } else if api["api_name"] == "std::process::arg_len" {
            Some("lanius_std")
        } else if api["api_name"] == "std::process::arg_read" {
            Some("lanius_std")
        } else if api["api_name"] == "std::io::write_stdout" {
            Some("compiler_host_stdio")
        } else if api["api_name"] == "std::io::write_stderr" {
            Some("compiler_host_stdio")
        } else if api["api_name"] == "std::io::read_stdin" {
            Some("compiler_host_stdio")
        } else {
            None
        };
        if let Some(extern_abi) = expected_extern_abi {
            return api["extern_abi"] == extern_abi
                && api["current_status"] == "executable-compiler-primitive"
                && api["executable"] == true;
        }
        api["current_status"] == "known-unbound" && api["executable"] == false
    }

    #[test]
    fn diagnostic_code_registry_is_unique_sorted_and_lookupable() {
        let mut previous = "";
        for diagnostic in DIAGNOSTIC_CODE_REGISTRY {
            assert!(
                diagnostic.code.starts_with("LNC"),
                "diagnostic codes should use the public LNC prefix: {:?}",
                diagnostic
            );
            assert_eq!(
                diagnostic.code.len(),
                7,
                "diagnostic codes should be stable LNC#### identifiers"
            );
            assert!(
                diagnostic.code > previous,
                "diagnostic registry should stay sorted and unique"
            );
            assert!(
                !diagnostic.title.is_empty() && !diagnostic.category.is_empty(),
                "diagnostic registry entries should have external-facing metadata"
            );
            assert_eq!(
                diagnostic.default_severity,
                DiagnosticSeverity::Error,
                "registry entries should expose the default CLI/LSP severity"
            );
            assert_eq!(
                diagnostic.lsp_source, LSP_DIAGNOSTIC_SOURCE,
                "registry entries should expose the LSP diagnostic source"
            );
            assert_eq!(
                diagnostic.lsp_severity, LSP_DIAGNOSTIC_ERROR_SEVERITY,
                "registry entries should expose the LSP DiagnosticSeverity number"
            );
            assert_eq!(
                diagnostic_code_info(diagnostic.code),
                Some(diagnostic),
                "registry lookup should return the documented entry"
            );
            previous = diagnostic.code;
        }

        assert!(
            diagnostic_code_info("LNC9999").is_none(),
            "unknown diagnostic codes should not resolve"
        );
    }

    #[test]
    fn diagnostic_public_code_inputs_are_canonicalized() {
        let info = diagnostic_code_info(" lnc0017 ")
            .expect("diagnostic registry lookup should normalize public code input");
        assert_eq!(info.code, "LNC0017");
        assert_eq!(info.title, "x86 backend boundary");

        let diagnostic = Diagnostic::error(" lnc0017 ", "backend boundary");
        assert_eq!(diagnostic.code, "LNC0017");
        assert_eq!(diagnostic.title, "x86 backend boundary");
        assert_eq!(diagnostic.category, "native codegen");
        assert_eq!(
            diagnostic.explain_command,
            "laniusc diagnostics explain LNC0017"
        );
        assert_eq!(
            unsupported_feature_diagnostic_info(" lnc0017 ")
                .expect("unsupported-feature lookup should normalize public code input")
                .boundary,
            "x86 backend"
        );
        assert_eq!(
            codegen_boundary_diagnostic_info(" lnc0017 ")
                .expect("codegen-boundary lookup should normalize public code input")
                .target,
            "x86_64"
        );

        let explanation = diagnostic_explanation(" lnc9999 ");
        assert_eq!(explanation.requested_code, "LNC9999");
        assert!(!explanation.known);
        assert_eq!(
            diagnostic_explain_command(" lnc0017 "),
            "laniusc diagnostics explain LNC0017"
        );
    }

    #[test]
    #[cfg(debug_assertions)]
    #[should_panic(expected = "diagnostic code LNC9999 is not registered")]
    fn diagnostic_creation_rejects_unregistered_codes_in_debug_builds() {
        let _ = Diagnostic::error("LNC9999", "not externally registered");
    }

    #[test]
    fn diagnostic_code_registry_preserves_public_metadata() {
        let expected = [
            (
                "LNC0001",
                "missing source-root module",
                "package/import loading",
            ),
            ("LNC0002", "import cycle", "module resolution"),
            (
                "LNC0003",
                "ambiguous source-root module",
                "package/import loading",
            ),
            ("LNC0004", "source-root escape", "package/import loading"),
            ("LNC0005", "unresolved identifier", "name resolution"),
            ("LNC0006", "type mismatch", "type checking"),
            ("LNC0007", "unknown type", "type checking"),
            ("LNC0008", "unsatisfied trait bound", "trait solving"),
            ("LNC0009", "ambiguous trait bound", "trait solving"),
            ("LNC0010", "unresolved import", "module resolution"),
            ("LNC0011", "unsupported import form", "module resolution"),
            ("LNC0012", "import path too deep", "module resolution"),
            (
                "LNC0013",
                "duplicate module declaration",
                "module resolution",
            ),
            ("LNC0014", "module path too deep", "module resolution"),
            ("LNC0015", "invalid module path", "module resolution"),
            ("LNC0016", "syntax error", "parsing"),
            ("LNC0017", "x86 backend boundary", "native codegen"),
            ("LNC0018", "unsupported CLI option value", "tooling"),
            ("LNC0019", "formatter check failed", "tooling"),
            ("LNC0020", "unknown CLI option", "tooling"),
            ("LNC0021", "invalid trait implementation", "trait solving"),
            (
                "LNC0022",
                "linked-output contract descriptor",
                "native codegen",
            ),
            ("LNC0023", "missing CLI option value", "tooling"),
            (
                "LNC0024",
                "source-root package boundary",
                "package/import loading",
            ),
            ("LNC0025", "missing CLI subcommand", "tooling"),
            ("LNC0026", "missing CLI argument", "tooling"),
            ("LNC0027", "call resolution failed", "type checking"),
            ("LNC0028", "unsupported LSP method", "tooling"),
            ("LNC0029", "invalid LSP message", "tooling"),
            (
                "LNC0030",
                "non-source source-root module",
                "package/import loading",
            ),
            ("LNC0031", "unexpected CLI argument", "tooling"),
            ("LNC0032", "incompatible CLI options", "tooling"),
            ("LNC0033", "invalid generic parameter list", "type checking"),
            ("LNC0034", "output write failed", "tooling"),
            ("LNC0035", "output stream write failed", "tooling"),
            ("LNC0036", "WASM backend boundary", "target codegen"),
            (
                "LNC0037",
                "package metadata invalid",
                "package/import loading",
            ),
            ("LNC0038", "runtime service boundary", "runtime binding"),
            ("LNC0039", "unknown CLI subcommand", "tooling"),
            ("LNC0040", "input read failed", "tooling"),
            ("LNC0041", "invalid loop control", "type checking"),
            ("LNC0042", "invalid member access", "type checking"),
            ("LNC0043", "invalid array return", "type checking"),
            ("LNC0044", "compiler limit exceeded", "type checking"),
            (
                "LNC0045",
                "unclassified type-check rejection",
                "type checking",
            ),
            ("LNC0046", "source tokenization failed", "parsing"),
            ("LNC0047", "type-check execution failed", "type checking"),
            (
                "LNC0048",
                "source-pack input limit exceeded",
                "package/import loading",
            ),
            (
                "LNC0049",
                "explicit source-pack manifest invalid",
                "package/import loading",
            ),
            (
                "LNC0050",
                "source-pack library partition invalid",
                "package/import loading",
            ),
            (
                "LNC0051",
                "source-pack artifact manifest invalid",
                "package/import loading",
            ),
            (
                "LNC0052",
                "source-pack artifact shard metadata invalid",
                "package/import loading",
            ),
            (
                "LNC0053",
                "package manifest invalid",
                "package/import loading",
            ),
            (
                "LNC0054",
                "package manifest could not be read",
                "package/import loading",
            ),
            (
                "LNC0055",
                "package lockfile invalid",
                "package/import loading",
            ),
            (
                "LNC0056",
                "package lockfile could not be read or written",
                "package/import loading",
            ),
            ("LNC0057", "compiler execution failed", "tooling"),
            (
                "LNC0058",
                "source-pack progress state invalid",
                "package/import loading",
            ),
            (
                "LNC0059",
                "source-pack artifact store failed",
                "package/import loading",
            ),
            (
                "LNC0060",
                "source-pack metadata store failed",
                "package/import loading",
            ),
            (
                "LNC0061",
                "source-root input invalid",
                "package/import loading",
            ),
            (
                "LNC0062",
                "source-pack target invalid",
                "package/import loading",
            ),
            (
                "LNC0063",
                "source-pack work queue invalid",
                "package/import loading",
            ),
            (
                "LNC0064",
                "source-pack preparation incomplete",
                "package/import loading",
            ),
            (
                "LNC0065",
                "source-pack preparation limit invalid",
                "package/import loading",
            ),
            ("LNC0066", "parser execution failed", "parsing"),
            ("LNC0067", "CLI operation failed", "tooling"),
        ];

        assert_eq!(DIAGNOSTIC_CODE_REGISTRY.len(), expected.len());
        for (diagnostic, (code, title, category)) in DIAGNOSTIC_CODE_REGISTRY.iter().zip(expected) {
            assert_eq!(diagnostic.code, code);
            assert_eq!(diagnostic.title, title);
            assert_eq!(diagnostic.category, category);
            assert_eq!(diagnostic.default_severity, DiagnosticSeverity::Error);
            assert_eq!(diagnostic.lsp_source, LSP_DIAGNOSTIC_SOURCE);
            assert_eq!(diagnostic.lsp_severity, LSP_DIAGNOSTIC_ERROR_SEVERITY);
        }
    }

    #[test]
    fn diagnostic_code_registry_json_is_tool_readable() {
        let json = diagnostic_code_registry_json_pretty().expect("registry should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("registry JSON should parse");
        let entries = value.as_array().expect("registry JSON should be an array");
        assert_eq!(entries.len(), DIAGNOSTIC_CODE_REGISTRY.len());
        assert_eq!(entries[0]["code"], "LNC0001");
        assert_eq!(entries[0]["title"], "missing source-root module");
        assert_eq!(entries[0]["category"], "package/import loading");
        assert_eq!(entries[0]["default_severity"], "error");
        assert_eq!(entries[0]["lsp_source"], LSP_DIAGNOSTIC_SOURCE);
        assert_eq!(entries[0]["lsp_severity"], LSP_DIAGNOSTIC_ERROR_SEVERITY);
    }

    #[test]
    fn unsupported_feature_diagnostics_json_is_tool_readable() {
        let json = unsupported_feature_diagnostics_json_pretty()
            .expect("unsupported-feature registry should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("unsupported-feature JSON should parse");
        let entries = value
            .as_array()
            .expect("unsupported-feature JSON should be an array");
        assert_eq!(entries.len(), UNSUPPORTED_FEATURE_DIAGNOSTICS.len());
        assert_eq!(entries[0]["code"], "LNC0011");
        assert_eq!(entries[0]["boundary"], "import form");
        assert!(entries[0]["summary"].as_str().unwrap().contains("import"));
        assert!(entries[0]["next_step"].as_str().unwrap().contains("import"));
    }

    #[test]
    fn runtime_service_boundary_diagnostics_describe_fail_closed_services() {
        let json = runtime_service_boundary_diagnostics_json_pretty()
            .expect("runtime-service boundary registry should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("runtime-service boundary JSON should parse");
        let entries = value
            .as_array()
            .expect("runtime-service boundary JSON should be an array");
        assert_eq!(entries.len(), RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.len());

        let mut previous_service_id = 0;
        for entry in RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS {
            assert_eq!(entry.diagnostic_code, "LNC0038");
            assert!(
                entry.service_id > previous_service_id,
                "runtime service diagnostic rows should be in canonical service-id order"
            );
            assert!(!entry.service_name.is_empty());
            assert!(entry.module_path.contains("::"));
            assert!(entry.capability_constant.ends_with("_HAS_RUNTIME_BINDING"));
            assert!(entry.status_probe.ends_with("_service_status()"));
            assert!(entry.binding_probe.contains("runtime_binding()"));
            assert_eq!(
                entry.accepted_selector_kinds,
                RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS
            );
            assert_eq!(entry.current_status, "known-unbound");
            assert!(!entry.executable);
            assert_eq!(
                runtime_service_boundary_diagnostic_info(entry.service_id),
                Some(entry),
                "runtime service lookup should return the public row"
            );
            previous_service_id = entry.service_id;
        }
        assert!(runtime_service_boundary_diagnostic_info(0).is_none());
        assert!(runtime_service_boundary_diagnostic_info(99).is_none());

        let stdio = entries
            .iter()
            .find(|entry| entry["service_id"] == 3)
            .expect("stdio service row should be present");
        assert_eq!(stdio["diagnostic_code"], "LNC0038");
        assert_eq!(stdio["module_path"], "std::io");
        assert_eq!(stdio["binding_probe"], "stdio_requires_runtime_binding()");
        assert_eq!(
            stdio["accepted_selector_kinds"],
            serde_json::json!(RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS)
        );
        assert_eq!(stdio["current_status"], "known-unbound");
        assert_eq!(stdio["executable"], false);
    }

    #[test]
    fn runtime_bound_api_diagnostics_describe_fail_closed_public_apis() {
        let json = runtime_bound_api_diagnostics_json_pretty()
            .expect("runtime-bound API registry should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("runtime-bound API JSON should parse");
        let entries = value
            .as_array()
            .expect("runtime-bound API JSON should be an array");
        assert_eq!(entries.len(), RUNTIME_BOUND_API_DIAGNOSTICS.len());

        let mut previous_service_id = 0;
        for entry in RUNTIME_BOUND_API_DIAGNOSTICS {
            assert_eq!(entry.diagnostic_code, "LNC0038");
            assert!(
                entry.service_id >= previous_service_id,
                "runtime-bound API rows should be grouped by canonical service-id order"
            );
            let service = runtime_service_boundary_diagnostic_info(entry.service_id)
                .expect("runtime-bound API rows should point at a known service boundary");
            assert_eq!(
                entry.service_capability_constant, service.capability_constant,
                "runtime-bound API rows should carry the owning service capability constant"
            );
            assert_eq!(
                entry.service_module_path, service.module_path,
                "runtime-bound API rows should carry the owning service module path"
            );
            assert_eq!(
                entry.service_status_probe, service.status_probe,
                "runtime-bound API rows should carry the owning service status probe"
            );
            assert_eq!(
                entry.service_binding_probe, service.binding_probe,
                "runtime-bound API rows should point at a known service boundary"
            );
            assert!(entry.module_path.contains("::"));
            assert!(entry.api_name.starts_with(entry.module_path));
            assert!(entry.executable_probe.ends_with("_is_executable()"));
            assert!(entry.binding_probe.contains("runtime_binding()"));
            assert_eq!(
                entry.accepted_selector_kinds,
                RUNTIME_BOUND_API_SELECTOR_KINDS
            );
            assert!(api_info_has_expected_status(entry));
            assert_eq!(
                runtime_bound_api_diagnostic_info(entry.api_name),
                Some(entry),
                "runtime-bound API lookup should return the public row"
            );
            previous_service_id = entry.service_id;
        }

        let write_stdout = entries
            .iter()
            .find(|entry| entry["api_name"] == "std::io::write_stdout")
            .expect("stdio write_stdout API row should be present");
        assert_eq!(write_stdout["diagnostic_code"], "LNC0038");
        assert_eq!(write_stdout["service_id"], 3);
        let stdio_service = runtime_service_boundary_diagnostic_info(3)
            .expect("stdio service boundary row should be public");
        assert_eq!(
            write_stdout["service_capability_constant"],
            stdio_service.capability_constant
        );
        assert_eq!(
            write_stdout["service_module_path"],
            stdio_service.module_path
        );
        assert_eq!(
            write_stdout["service_status_probe"],
            stdio_service.status_probe
        );
        assert_eq!(
            write_stdout["service_binding_probe"],
            stdio_service.binding_probe
        );
        assert_eq!(write_stdout["module_path"], "std::io");
        assert_eq!(
            write_stdout["executable_probe"],
            "write_stdout_is_executable()"
        );
        assert_eq!(
            write_stdout["binding_probe"],
            "write_stdout_requires_runtime_binding()"
        );
        assert_eq!(
            write_stdout["accepted_selector_kinds"],
            serde_json::json!(RUNTIME_BOUND_API_SELECTOR_KINDS)
        );
        assert_eq!(
            write_stdout["current_status"],
            "executable-compiler-primitive"
        );
        assert_eq!(write_stdout["executable"], true);
        let print_i32 = entries
            .iter()
            .find(|entry| entry["api_name"] == "std::io::print_i32")
            .expect("stdio print_i32 API row should be present");
        assert_eq!(print_i32["service_id"], 3);
        assert_eq!(print_i32["module_path"], "std::io");
        assert_eq!(print_i32["extern_abi"], "compiler_print_i32");
        assert_eq!(print_i32["executable_probe"], "print_i32_is_executable()");
        assert_eq!(
            print_i32["binding_probe"],
            "print_i32_requires_runtime_binding()"
        );
        assert!(api_json_has_expected_status(print_i32));
        assert!(runtime_bound_api_diagnostic_info("std::io::println").is_none());
    }

    #[test]
    fn diagnostic_explanation_json_describes_known_and_unknown_codes() {
        let json = diagnostic_explanation_json_pretty("lnc0017")
            .expect("diagnostic explanation should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic explanation JSON should parse");
        assert_eq!(
            value["schema_version"],
            DIAGNOSTIC_EXPLANATION_SCHEMA_VERSION
        );
        assert_eq!(value["schema_name"], DIAGNOSTIC_EXPLANATION_SCHEMA_NAME);
        assert_eq!(
            value["registry_schema_version"],
            DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
        );
        assert_eq!(value["requested_code"], "LNC0017");
        assert_eq!(
            value["explain_command"],
            "laniusc diagnostics explain LNC0017"
        );
        assert_eq!(value["known"], true);
        assert_eq!(value["diagnostic"]["code"], "LNC0017");
        assert_eq!(value["diagnostic"]["title"], "x86 backend boundary");
        assert_eq!(value["diagnostic"]["category"], "native codegen");
        assert_eq!(value["diagnostic"]["default_severity"], "error");
        assert_eq!(value["diagnostic"]["lsp_source"], LSP_DIAGNOSTIC_SOURCE);
        assert_eq!(
            value["diagnostic"]["lsp_severity"],
            LSP_DIAGNOSTIC_ERROR_SEVERITY
        );
        assert_eq!(value["unsupported_feature"]["code"], "LNC0017");
        assert_eq!(value["unsupported_feature"]["boundary"], "x86 backend");
        assert!(
            value["unsupported_feature"]["next_step"]
                .as_str()
                .expect("unsupported-feature next step should be a string")
                .contains("--emit=wasm")
        );
        assert_eq!(value["codegen_boundary"]["diagnostic_code"], "LNC0017");
        assert_eq!(value["codegen_boundary"]["boundary"], "x86 backend");
        assert_eq!(value["codegen_boundary"]["target"], "x86_64");
        assert_eq!(
            value["codegen_boundary"]["stage"],
            "native codegen lowering"
        );
        assert_eq!(
            value["codegen_boundary"]["partial_artifact_policy"],
            "fail-closed before emitting a partial instruction prefix"
        );
        assert_eq!(value["codegen_boundary"]["target_bytes_emitted"], false);
        assert_eq!(
            value["codegen_boundary"]["diagnostics_only_command"],
            "laniusc check"
        );
        assert_eq!(value["codegen_boundary"]["fallback_emit"], "wasm");
        assert!(value["runtime_service_boundaries"].is_null());
        assert!(value["runtime_bound_apis"].is_null());

        let copied_json = diagnostic_explanation_json_pretty("error[lnc0017]: x86 backend")
            .expect("copied diagnostic explanation should serialize");
        let copied: serde_json::Value = serde_json::from_str(&copied_json)
            .expect("copied diagnostic explanation JSON should parse");
        assert_eq!(copied["requested_code"], "LNC0017");
        assert_eq!(copied["known"], true);
        assert_eq!(copied["diagnostic"]["code"], "LNC0017");
        assert_eq!(copied["codegen_boundary"]["target"], "x86_64");

        let runtime_json = diagnostic_explanation_json_pretty("lnc0038")
            .expect("runtime diagnostic explanation should serialize");
        let runtime: serde_json::Value = serde_json::from_str(&runtime_json)
            .expect("runtime diagnostic explanation JSON should parse");
        assert_eq!(runtime["requested_code"], "LNC0038");
        assert_eq!(runtime["known"], true);
        assert_eq!(
            runtime["unsupported_feature"]["boundary"],
            "runtime service binding"
        );
        let runtime_services = runtime["runtime_service_boundaries"]
            .as_array()
            .expect("runtime diagnostic explanation should include service rows");
        assert_eq!(
            runtime_services.len(),
            RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.len()
        );
        assert!(runtime_services.iter().all(|service| {
            service["diagnostic_code"] == "LNC0038"
                && service["accepted_selector_kinds"]
                    == serde_json::json!(RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS)
                && service["current_status"] == "known-unbound"
                && service["executable"] == false
        }));
        let runtime_apis = runtime["runtime_bound_apis"]
            .as_array()
            .expect("runtime diagnostic explanation should include API rows");
        assert_eq!(runtime_apis.len(), RUNTIME_BOUND_API_DIAGNOSTICS.len());
        assert!(runtime_apis.iter().any(|api| {
            api["api_name"] == "std::io::write_stdout"
                && api["service_id"] == 3
                && api["binding_probe"] == "write_stdout_requires_runtime_binding()"
                && api["accepted_selector_kinds"]
                    == serde_json::json!(RUNTIME_BOUND_API_SELECTOR_KINDS)
                && api["executable"] == false
        }));
        assert!(runtime_apis.iter().all(|api| {
            let service_id = api["service_id"]
                .as_u64()
                .and_then(|service_id| u32::try_from(service_id).ok());
            let service = service_id.and_then(runtime_service_boundary_diagnostic_info);
            api["diagnostic_code"] == "LNC0038"
                && api["accepted_selector_kinds"]
                    == serde_json::json!(RUNTIME_BOUND_API_SELECTOR_KINDS)
                && api_json_has_expected_status(api)
                && service.is_some_and(|service| {
                    api["service_capability_constant"] == service.capability_constant
                        && api["service_module_path"] == service.module_path
                        && api["service_status_probe"] == service.status_probe
                        && api["service_binding_probe"] == service.binding_probe
                })
        }));

        let unknown_json = diagnostic_explanation_json_pretty("LNC9999")
            .expect("unknown diagnostic explanation should serialize");
        let unknown: serde_json::Value = serde_json::from_str(&unknown_json)
            .expect("unknown diagnostic explanation JSON should parse");
        assert_eq!(
            unknown["schema_version"],
            DIAGNOSTIC_EXPLANATION_SCHEMA_VERSION
        );
        assert_eq!(unknown["schema_name"], DIAGNOSTIC_EXPLANATION_SCHEMA_NAME);
        assert_eq!(unknown["requested_code"], "LNC9999");
        assert_eq!(
            unknown["explain_command"],
            "laniusc diagnostics explain LNC9999"
        );
        assert_eq!(unknown["known"], false);
        assert!(unknown["diagnostic"].is_null());
        assert!(unknown["unsupported_feature"].is_null());
        assert!(unknown["codegen_boundary"].is_null());
        assert!(unknown["runtime_service_boundaries"].is_null());
        assert!(unknown["runtime_bound_apis"].is_null());
    }

    #[test]
    fn diagnostic_categories_are_stable_and_cover_registry() {
        assert_eq!(
            DIAGNOSTIC_CATEGORIES,
            &[
                "module resolution",
                "name resolution",
                "native codegen",
                "package/import loading",
                "parsing",
                "runtime binding",
                "target codegen",
                "tooling",
                "trait solving",
                "type checking",
            ]
        );

        let mut previous = "";
        for category in DIAGNOSTIC_CATEGORIES {
            assert!(!category.is_empty());
            assert!(
                *category > previous,
                "diagnostic categories should stay sorted and unique"
            );
            previous = *category;
        }

        for diagnostic in DIAGNOSTIC_CODE_REGISTRY {
            assert!(
                diagnostic_category_is_registered(diagnostic.category),
                "diagnostic {} should use a registered category",
                diagnostic.code
            );
        }
        assert!(!diagnostic_category_is_registered("backend internals"));
    }

    #[test]
    fn unsupported_feature_diagnostic_registry_maps_only_known_codes() {
        let expected = [
            (
                "LNC0011",
                "import form",
                "the module resolver understood the import position but rejected the import shape",
                "use module-path imports such as `import app::module;`; quoted imports are not supported in this edition",
            ),
            (
                "LNC0012",
                "import path depth",
                "the import path exceeded the compiler's currently supported module depth",
                "shorten or flatten the import path before compiling with this edition",
            ),
            (
                "LNC0014",
                "module path depth",
                "the declared module path exceeded the compiler's currently supported module depth",
                "shorten or flatten the module declaration before compiling with this edition",
            ),
            (
                "LNC0017",
                "x86 backend",
                "the program reached a native-codegen construct outside the current x86 lowering slice and is rejected instead of emitting a partial instruction prefix",
                "use `laniusc check` for diagnostics-only validation or `--emit=wasm` until this construct is covered by x86 lowering",
            ),
            (
                "LNC0022",
                "linked-output contract descriptor",
                "descriptor-mode linked output is expected to be JSON contract metadata, not executable bytes or incoherent descriptor data",
                "treat descriptor-mode linked output as JSON contract metadata; use non-descriptor compilation when target bytes are required",
            ),
            (
                "LNC0024",
                "source-root package boundary",
                "source-root loading rejected an import edge that crosses from stdlib roots back into package/user source roots",
                "keep stdlib modules independent from package/user roots; move shared APIs into stdlib roots or pass package sources through package manifest/lockfile metadata",
            ),
            (
                "LNC0036",
                "WASM backend",
                "the program reached a WASM-codegen construct outside the current WASM lowering support and is rejected instead of emitting a partial module prefix",
                "use `laniusc check` for diagnostics-only validation until this construct is covered by WASM lowering",
            ),
            (
                "LNC0038",
                "runtime service binding",
                "the program reached a stdlib or host API whose runtime service descriptor is known but not bound by the current linker/runtime contract",
                "treat the API as contract metadata only, check the matching `*_requires_runtime_binding()` helper, or supply a future runtime binding before emitting executable output",
            ),
        ];

        assert_eq!(UNSUPPORTED_FEATURE_DIAGNOSTICS.len(), expected.len());
        for (diagnostic, (code, boundary, summary, next_step)) in
            UNSUPPORTED_FEATURE_DIAGNOSTICS.iter().zip(expected)
        {
            assert_eq!(diagnostic.code, code);
            assert_eq!(diagnostic.boundary, boundary);
            assert_eq!(diagnostic.summary, summary);
            assert_eq!(diagnostic.next_step, next_step);
            assert!(
                diagnostic_code_info(code).is_some(),
                "unsupported-feature diagnostic {code} should be registered"
            );
            assert_eq!(
                unsupported_feature_diagnostic_info(code),
                Some(diagnostic),
                "unsupported-feature lookup should return the public mapping"
            );
        }

        assert!(
            unsupported_feature_diagnostic_info("LNC0016").is_none(),
            "syntax errors are not unsupported-feature boundaries"
        );
    }

    #[test]
    fn source_pack_nearest_file_uses_last_file_for_eof_offsets() {
        let paths = [
            Some(PathBuf::from("first.lani")),
            Some(PathBuf::from("second.lani")),
        ];
        let files =
            source_pack_diagnostic_files(&["module first;\n", "fn main() {}\n"], Some(&paths));
        let eof = files.last().expect("second source file").global_end;

        let file =
            source_pack_nearest_file_for_global_span(&files, eof).expect("nearest source file");

        assert_eq!(file.path, PathBuf::from("second.lani"));
    }

    #[test]
    fn source_pack_fallback_syntax_error_is_structured_and_user_facing() {
        let paths = [Some(PathBuf::from("app.lani"))];
        let files = source_pack_diagnostic_files(&["fn main() {\n"], Some(&paths));

        let err = source_pack_fallback_syntax_error(&files[0], files[0].global_end + 16);

        let diagnostic = match err {
            super::super::CompileError::Diagnostic(diagnostic) => diagnostic,
            other => panic!("expected structured diagnostic, got {other:?}"),
        };
        assert_eq!(diagnostic.code, "LNC0016");
        assert_eq!(diagnostic.message, "syntax error");
        assert_eq!(
            diagnostic
                .primary_label
                .as_ref()
                .expect("primary label")
                .message,
            "invalid syntax here"
        );
        assert!(diagnostic.notes.is_empty());

        let rendered = diagnostic.render();
        assert!(!rendered.contains("source-pack"));
        assert!(!rendered.contains("token readback"));
        assert!(!rendered.contains("nearest source"));
        assert!(!rendered.contains("could not pinpoint"));
    }

    #[test]
    fn lexical_syntax_error_labels_unknown_token_at_source_span() {
        let source = "fn main() { let x = @; }\n";
        let at = source.find('@').expect("source should contain @");

        let err = lexical_syntax_error_to_compile_error(Path::new("bad.lani"), source)
            .expect("unknown token should produce a lexical syntax diagnostic");

        match err {
            super::super::CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0016");
                assert_eq!(diagnostic.message, "unknown start of token: `@`");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("lexical syntax diagnostic should carry a primary label");
                assert_eq!(label.path, PathBuf::from("bad.lani"));
                assert_eq!(label.line, 1);
                assert_eq!(label.column, at + 1);
                assert_eq!(label.byte_start, Some(at));
                assert_eq!(label.byte_end, Some(at + 1));
                assert_eq!(label.message, "unknown start of token: `@`");
            }
            other => panic!("expected structured lexical diagnostic, got {other:?}"),
        }
    }

    #[test]
    fn lexical_syntax_error_reports_unterminated_block_comment() {
        let source = "fn main() {\n    /* missing close\n}\n";

        let err = lexical_syntax_error_to_compile_error(Path::new("comment.lani"), source)
            .expect("unterminated block comment should produce a lexical syntax diagnostic");

        match err {
            super::super::CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0016");
                assert_eq!(diagnostic.message, "unterminated block comment");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("unterminated comment diagnostic should carry a primary label");
                assert_eq!(label.line, 2);
                assert_eq!(label.column, 5);
                assert_eq!(label.message, "unterminated block comment");
            }
            other => panic!("expected structured lexical diagnostic, got {other:?}"),
        }
    }

    #[test]
    fn lexical_syntax_error_ignores_plain_parser_errors() {
        assert!(
            lexical_syntax_error_to_compile_error(
                Path::new("parser-error.lani"),
                "fn fn main() { return 0; }\n"
            )
            .is_none(),
            "lexical pre-check should leave ordinary parser errors to parser diagnostics"
        );
    }

    #[test]
    fn parser_rejection_label_targets_duplicate_function_keyword_after_fn() {
        let source = "fn fn main() { return 0; }\n";
        let previous = Token {
            kind: TokenKind::Fn,
            start: 0,
            len: 2,
        };
        let rejected = Token {
            kind: TokenKind::Fn,
            start: 3,
            len: 2,
        };

        let (target, message) =
            parser_rejection_label_target(source, &rejected, Some(&previous), None);
        assert_eq!(target.start, rejected.start);
        assert_eq!(message, "expected function name, found keyword `fn`");

        let (target, message) =
            parser_rejection_label_target(source, &previous, None, Some(&rejected));
        assert_eq!(target.start, rejected.start);
        assert_eq!(message, "expected function name, found keyword `fn`");

        let source_next = next_source_token(source, &previous)
            .expect("source-neighbor scan should find the duplicate keyword");
        let (target, message) =
            parser_rejection_label_target(source, &previous, None, Some(&source_next));
        assert_eq!(target.start, rejected.start);
        assert_eq!(message, "expected function name, found keyword `fn`");
    }

    #[test]
    fn source_context_label_targets_missing_return_semicolon() {
        let source = "fn main() { return 0 }\n";
        let close_brace = source.find('}').expect("source should contain }");

        let label = source_context_syntax_label(source)
            .expect("missing return semicolon should produce a source-context label");

        assert_eq!(label.start, close_brace);
        assert_eq!(label.len, 1);
        assert_eq!(label.message, "expected ';' after return statement");
    }

    #[test]
    fn source_context_label_ignores_braced_return_expression_with_semicolon() {
        let source = "fn main() { return Point { x: 1 }; }\n";

        assert!(
            source_context_syntax_label(source).is_none(),
            "braced expression followed by a semicolon should not look like a missing terminator"
        );
    }

    #[test]
    fn source_context_label_targets_missing_assignment_expression() {
        let source = "fn main() { let x = ; return 0; }\n";
        let semicolon = source.find(';').expect("source should contain ;");

        let label = source_context_syntax_label(source)
            .expect("missing assignment expression should produce a source-context label");

        assert_eq!(label.start, semicolon);
        assert_eq!(label.len, 1);
        assert_eq!(label.message, "expected expression after `=`");
    }

    #[test]
    fn source_context_label_ignores_assignment_with_expression() {
        let source = "fn main() { let x = 1; return x; }\n";

        assert!(
            source_context_syntax_label(source).is_none(),
            "assignment with an expression should not look like a missing initializer"
        );
    }

    #[test]
    fn source_context_label_targets_missing_import_path() {
        let source = "module app::main;\nimport ;\n";
        let semicolon = source
            .lines()
            .next()
            .map(|line| line.len() + 1)
            .unwrap_or(0)
            + "import ".len();

        let label = source_context_syntax_label(source)
            .expect("missing import path should produce a source-context label");

        assert_eq!(label.start, semicolon);
        assert_eq!(label.len, 1);
        assert_eq!(label.message, "expected module path after `import`");
    }

    #[test]
    fn source_context_label_targets_missing_module_path() {
        let source = "module ;\nfn main() { return 0; }\n";
        let semicolon = source.find(';').expect("source should contain ;");

        let label = source_context_syntax_label(source)
            .expect("missing module path should produce a source-context label");

        assert_eq!(label.start, semicolon);
        assert_eq!(label.len, 1);
        assert_eq!(label.message, "expected module path after `module`");
    }

    #[test]
    fn source_context_label_explains_bad_module_path_start_token() {
        let source = "module app::main;\nimport \"app/helper.lani\";\n";
        let quote = source
            .find('"')
            .expect("source should contain string import");

        let label = source_context_syntax_label(source)
            .expect("bad import path start should produce a source-context label");

        assert_eq!(label.start, quote);
        assert_eq!(label.len, "\"app/helper.lani\"".len());
        assert_eq!(
            label.message,
            "expected module path after `import`, found string literal"
        );
    }

    fn tiny_identifier_table() -> PrecomputedParseTables {
        let n_kinds = crate::lexer::tables::tokens::N_KINDS;
        let mut tables = PrecomputedParseTables::new(n_kinds, 1);
        tables.n_nonterminals = 1;
        tables.start_nonterminal = 0;
        tables.ll1_predict = vec![crate::parser::tables::INVALID_TABLE_ENTRY; n_kinds as usize];
        tables.ll1_predict[TokenKind::Ident as usize] = 0;
        tables.prod_rhs_off = vec![0];
        tables.prod_rhs_len = vec![1];
        tables.prod_rhs = vec![TokenKind::Ident as u32];
        tables
    }

    fn tiny_identifier_semicolon_table() -> PrecomputedParseTables {
        let n_kinds = crate::lexer::tables::tokens::N_KINDS;
        let mut tables = PrecomputedParseTables::new(n_kinds, 1);
        tables.n_nonterminals = 1;
        tables.start_nonterminal = 0;
        tables.ll1_predict = vec![crate::parser::tables::INVALID_TABLE_ENTRY; n_kinds as usize];
        tables.ll1_predict[TokenKind::Ident as usize] = 0;
        tables.prod_rhs_off = vec![0];
        tables.prod_rhs_len = vec![2];
        tables.prod_rhs = vec![TokenKind::Ident as u32, TokenKind::Semicolon as u32];
        tables
    }

    #[test]
    fn ll1_rejection_context_label_reports_expected_identifier() {
        let source = "fn main() {}\n";
        let tables = tiny_identifier_table();
        let failure = ParserFailure::from_ll1_rejection(
            crate::parser::driver::Ll1AcceptResult {
                accepted: false,
                error_pos: 1,
                error_code: 2,
                detail: 0,
                steps: 1,
                emit_len: 0,
            },
            &tables,
            Some(vec![0, TokenKind::Fn as u32, 0]),
        );
        let label = ll1_rejection_syntax_label_for_source(source, &failure)
            .expect("LL(1) table context should produce a syntax label");

        assert_eq!(label.start, 0);
        assert_eq!(label.len, "fn".len());
        assert_eq!(label.message, "expected identifier, found keyword `fn`");
    }

    #[test]
    fn ll1_rejection_context_label_maps_source_pack_file() {
        let paths = [
            Some(PathBuf::from("first.lani")),
            Some(PathBuf::from("second.lani")),
        ];
        let files = source_pack_diagnostic_files(&["value ", "{\n"], Some(&paths));
        let tables = tiny_identifier_semicolon_table();
        let failure = ParserFailure::from_ll1_rejection(
            crate::parser::driver::Ll1AcceptResult {
                accepted: false,
                error_pos: 2,
                error_code: 2,
                detail: 0,
                steps: 2,
                emit_len: 0,
            },
            &tables,
            Some(vec![
                0,
                TokenKind::Ident as u32,
                TokenKind::LBrace as u32,
                0,
            ]),
        );

        let (file, label) = ll1_rejection_syntax_label_for_source_pack(&files, &failure)
            .expect("source-pack table context should produce a syntax label");

        assert_eq!(file.path, PathBuf::from("second.lani"));
        assert_eq!(label.start, 0);
        assert_eq!(label.len, 1);
        assert_eq!(label.message, "expected `;`, found `{`");
    }

    #[test]
    fn expected_syntax_terminal_description_hides_parser_retags() {
        assert_eq!(
            expected_syntax_terminal_description(TokenKind::FnBlockLBrace as u32),
            "`{`"
        );
        assert_eq!(
            expected_syntax_terminal_description(TokenKind::LetIdent as u32),
            "identifier"
        );
    }

    #[test]
    fn source_context_rules_prioritize_missing_assignment_expression() {
        let source = "fn main() { let x = }\n";
        let close_brace = source.find('}').expect("source should contain }");

        let label = source_context_syntax_label(source)
            .expect("missing assignment expression should win over missing let semicolon");

        assert_eq!(label.start, close_brace);
        assert_eq!(label.len, 1);
        assert_eq!(label.message, "expected expression after `=`");
    }

    #[test]
    fn source_context_label_targets_missing_if_block() {
        let source = "fn main() { if (true) return 0; }\n";
        let return_start = source.find("return").expect("source should contain return");

        let label = source_context_syntax_label(source)
            .expect("missing if block should produce a source-context label");

        assert_eq!(label.start, return_start);
        assert_eq!(label.len, "return".len());
        assert_eq!(
            label.message,
            "expected `{` after if condition, found keyword `return`"
        );
    }

    #[test]
    fn source_context_label_targets_missing_while_block() {
        let source = "fn main() { while (true) return 0; }\n";
        let return_start = source.find("return").expect("source should contain return");

        let label = source_context_syntax_label(source)
            .expect("missing while block should produce a source-context label");

        assert_eq!(label.start, return_start);
        assert_eq!(label.len, "return".len());
        assert_eq!(
            label.message,
            "expected `{` after while condition, found keyword `return`"
        );
    }

    #[test]
    fn source_context_label_ignores_braced_if_block() {
        let source = "fn main() { if (true) { return 0; } }\n";

        assert!(
            source_context_syntax_label(source).is_none(),
            "if condition followed by a block should not look like a missing block"
        );
    }

    #[test]
    fn diagnostic_renderer_includes_code_span_snippet_label_and_note() {
        let diagnostic = Diagnostic::error("LNC0001", "missing source-root module core::missing")
            .with_primary_label(DiagnosticLabel::primary(
                "app.lani",
                3,
                1,
                "import core::missing;".len(),
                Some("import core::missing;".to_string()),
                "imported here",
            ))
            .with_note("searched stdlib/core/missing.lani");

        assert_eq!(
            diagnostic.render(),
            "error[LNC0001]: missing source-root module core::missing\n --> app.lani:3:1\n  |\n3 | import core::missing;\n  | ^^^^^^^^^^^^^^^^^^^^^ imported here\n     = note: searched stdlib/core/missing.lani"
        );
    }

    #[test]
    fn diagnostic_renderers_omit_blank_help_and_notes() {
        let diagnostic = Diagnostic::error("LNC0020", "unknown CLI option")
            .with_help(" \t ")
            .with_note("")
            .with_note("   ")
            .with_note("try --help");

        let rendered = diagnostic.render();
        assert!(
            !rendered.contains("= help:"),
            "text diagnostics should not render blank help rows\n{rendered}"
        );
        assert_eq!(
            rendered.matches("= note:").count(),
            1,
            "text diagnostics should omit blank note rows\n{rendered}"
        );
        assert!(
            rendered.contains("= note: try --help"),
            "text diagnostics should keep nonblank note rows\n{rendered}"
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert!(
            value.get("help").is_none(),
            "JSON diagnostics should not publish a blank help field\n{json}"
        );
        assert_eq!(value["notes"], serde_json::json!(["try --help"]));
    }

    #[test]
    fn diagnostic_renderers_trim_public_help_and_notes() {
        let diagnostic = Diagnostic::error("LNC0020", "unknown CLI option")
            .with_help("  run `laniusc --help`  ")
            .with_note("\tunknown option: --wat  ");

        let rendered = diagnostic.render();
        assert!(
            rendered.contains("= help: run `laniusc --help`"),
            "text diagnostics should trim public help text\n{rendered}"
        );
        assert!(
            rendered.contains("= note: unknown option: --wat"),
            "text diagnostics should trim public notes\n{rendered}"
        );
        assert!(
            !rendered.contains("help:   ") && !rendered.contains("note: \t"),
            "text diagnostics should not preserve incidental caller whitespace\n{rendered:?}"
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["help"], "run `laniusc --help`");
        assert_eq!(value["notes"], serde_json::json!(["unknown option: --wat"]));

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("LSP diagnostic JSON should serialize");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert_eq!(lsp["data"]["help"], "run `laniusc --help`");
        assert_eq!(
            lsp["data"]["notes"],
            serde_json::json!(["unknown option: --wat"])
        );
    }

    #[test]
    fn diagnostic_renderers_normalize_public_text_control_whitespace() {
        let diagnostic = Diagnostic::error("LNC0016", "  syntax\nerror\tnear token  ")
            .with_primary_label(DiagnosticLabel::primary(
                "app.lani",
                1,
                1,
                3,
                Some("bad\tline".to_string()),
                "  invalid\nsyntax\there  ",
            ))
            .with_help("  run\n`laniusc check`\tfor diagnostics  ")
            .with_note(" parser\r\nstopped\tbefore recovery ");

        assert_eq!(diagnostic.message, "syntax error near token");
        let label = diagnostic
            .primary_label
            .as_ref()
            .expect("diagnostic should carry a primary label");
        assert_eq!(label.message, "invalid syntax here");
        assert_eq!(label.source_line.as_deref(), Some("bad\tline"));
        assert_eq!(
            diagnostic.help.as_deref(),
            Some("run `laniusc check` for diagnostics")
        );
        assert_eq!(
            diagnostic.notes,
            vec!["parser stopped before recovery".to_string()]
        );

        let rendered = diagnostic.render();
        assert!(
            rendered.contains("error[LNC0016]: syntax error near token"),
            "text diagnostics should normalize the primary message\n{rendered}"
        );
        assert!(
            rendered.contains("bad\tline"),
            "text diagnostics should preserve source snippets\n{rendered:?}"
        );
        assert!(
            rendered.contains("^^^ invalid syntax here"),
            "text diagnostics should normalize label messages\n{rendered}"
        );
        assert!(
            rendered.contains("= help: run `laniusc check` for diagnostics"),
            "text diagnostics should normalize help text\n{rendered}"
        );
        assert!(
            rendered.contains("= note: parser stopped before recovery"),
            "text diagnostics should normalize note text\n{rendered}"
        );
        assert!(
            !rendered.contains("syntax\nerror")
                && !rendered.contains("invalid\nsyntax")
                && !rendered.contains("parser\r\nstopped"),
            "public diagnostic text should not embed control newlines\n{rendered:?}"
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["message"], "syntax error near token");
        assert_eq!(value["primary_label"]["message"], "invalid syntax here");
        assert_eq!(value["primary_label"]["source_line"], "bad\tline");
        assert_eq!(value["help"], "run `laniusc check` for diagnostics");
        assert_eq!(
            value["notes"],
            serde_json::json!(["parser stopped before recovery"])
        );

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("LSP diagnostic JSON should serialize");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert_eq!(lsp["message"], "syntax error near token");
        assert_eq!(
            lsp["data"]["primary_label"]["message"],
            "invalid syntax here"
        );
        assert_eq!(lsp["data"]["help"], "run `laniusc check` for diagnostics");
        assert_eq!(
            lsp["data"]["notes"],
            serde_json::json!(["parser stopped before recovery"])
        );
    }

    #[test]
    fn diagnostic_renderers_deduplicate_public_notes_after_trimming() {
        let diagnostic = Diagnostic::error("LNC0020", "unknown CLI option")
            .with_note("  try `laniusc --help`  ")
            .with_note("try `laniusc --help`")
            .with_note("\ttry `laniusc --help`\n")
            .with_note("unknown option: --wat");

        assert_eq!(
            diagnostic.notes,
            vec![
                "try `laniusc --help`".to_string(),
                "unknown option: --wat".to_string()
            ]
        );

        let rendered = diagnostic.render();
        assert_eq!(
            rendered.matches("= note: try `laniusc --help`").count(),
            1,
            "text diagnostics should render duplicate notes once\n{rendered}"
        );
        assert_eq!(
            rendered.matches("= note:").count(),
            2,
            "text diagnostics should keep distinct notes\n{rendered}"
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(
            value["notes"],
            serde_json::json!(["try `laniusc --help`", "unknown option: --wat"])
        );

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("LSP diagnostic JSON should serialize");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert_eq!(
            lsp["data"]["notes"],
            serde_json::json!(["try `laniusc --help`", "unknown option: --wat"])
        );
    }

    #[test]
    fn diagnostic_constructor_trims_public_message() {
        let diagnostic = Diagnostic::error("LNC0020", "  unknown CLI option  ");

        assert_eq!(diagnostic.message, "unknown CLI option");
        assert_eq!(diagnostic.render(), "error[LNC0020]: unknown CLI option");

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["message"], "unknown CLI option");

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("LSP diagnostic JSON should serialize");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert_eq!(lsp["message"], "unknown CLI option");
    }

    #[test]
    fn diagnostic_constructor_uses_registry_title_for_blank_message() {
        let diagnostic = Diagnostic::error("LNC0020", " \t ");

        assert_eq!(diagnostic.title, "unknown CLI option");
        assert_eq!(diagnostic.message, "unknown CLI option");
        assert_eq!(diagnostic.render(), "error[LNC0020]: unknown CLI option");

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["message"], "unknown CLI option");

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("LSP diagnostic JSON should serialize");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert_eq!(lsp["message"], "unknown CLI option");
    }

    #[test]
    fn diagnostic_label_constructor_trims_public_message() {
        let diagnostic = Diagnostic::error("LNC0016", "syntax error").with_primary_label(
            DiagnosticLabel::primary(
                "app.lani",
                1,
                4,
                2,
                Some("fn fn main() {}".to_string()),
                "  expected function name  ",
            ),
        );

        let label = diagnostic
            .primary_label
            .as_ref()
            .expect("diagnostic should carry a primary label");
        assert_eq!(label.message, "expected function name");

        let rendered = diagnostic.render();
        assert!(
            rendered.contains("^^ expected function name"),
            "text diagnostics should render the trimmed label message\n{rendered}"
        );
        assert!(
            !rendered.contains("  expected function name  "),
            "text diagnostics should not preserve incidental caller whitespace\n{rendered:?}"
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["primary_label"]["message"], "expected function name");

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("LSP diagnostic JSON should serialize");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert_eq!(
            lsp["data"]["primary_label"]["message"],
            "expected function name"
        );
    }

    #[cfg(unix)]
    #[test]
    fn diagnostic_renderers_serialize_non_utf8_label_paths_as_display_paths() {
        use std::{ffi::OsString, os::unix::ffi::OsStringExt};

        let path = PathBuf::from(OsString::from_vec(vec![b's', b'r', b'c', b'/', 0xff]));
        let display_path = path.display().to_string();
        let diagnostic = Diagnostic::error("LNC0016", "syntax error").with_primary_label(
            DiagnosticLabel::primary(
                path,
                1,
                1,
                3,
                Some("bad".to_string()),
                "invalid syntax here",
            ),
        );

        let rendered = diagnostic.render();
        assert!(
            rendered.contains(&format!(" --> {display_path}:1:1")),
            "text diagnostics should render the display path\n{rendered}"
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize non-UTF8 paths through display form");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["code"], "LNC0016");
        assert_eq!(value["primary_label"]["path"], display_path);

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("LSP diagnostic JSON should serialize non-UTF8 paths through display form");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert_eq!(lsp["code"], "LNC0016");
        assert_eq!(lsp["data"]["primary_label"]["path"], display_path);
    }

    #[test]
    fn diagnostic_label_normalization_clamps_range_to_source_line() {
        let diagnostic = Diagnostic::error("LNC0016", "syntax error").with_primary_label(
            DiagnosticLabel::primary(
                "app.lani",
                1,
                8,
                20,
                Some("let x = 1;".to_string()),
                "range here",
            ),
        );

        let label = diagnostic
            .primary_label
            .as_ref()
            .expect("diagnostic should carry a primary label");
        assert_eq!(label.column, 8);
        assert_eq!(label.length, 3);

        let rendered = diagnostic.render();
        assert!(
            rendered.contains(" --> app.lani:1:8"),
            "text diagnostics should render the normalized column\n{rendered}"
        );
        assert!(
            !rendered.contains("^^^^"),
            "text diagnostics should not render carets beyond the source line\n{rendered}"
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["primary_label"]["column"], 8);
        assert_eq!(value["primary_label"]["length"], 3);

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("LSP diagnostic JSON should serialize");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert_eq!(lsp["range"]["start"]["character"], 7);
        assert_eq!(lsp["range"]["end"]["character"], 10);
    }

    #[test]
    fn diagnostic_renderers_note_missing_required_primary_label() {
        let diagnostic = Diagnostic::error("LNC0016", "syntax error");

        assert!(
            diagnostic.notes.is_empty(),
            "projection-only notes should not mutate the stored diagnostic"
        );

        let rendered = diagnostic.render();
        assert!(
            rendered.contains("= note: source location unavailable for this diagnostic"),
            "text diagnostics should explain why a required source label is absent\n{rendered}"
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["primary_label_policy"], "required");
        assert_eq!(value["primary_label"], serde_json::Value::Null);
        assert_eq!(
            value["notes"],
            serde_json::json!([MISSING_REQUIRED_PRIMARY_LABEL_NOTE])
        );
        assert!(
            diagnostic.notes.is_empty(),
            "JSON projection should not mutate the stored diagnostic"
        );

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("LSP diagnostic JSON should serialize");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert_eq!(lsp["data"]["primary_label_policy"], "required");
        assert_eq!(
            lsp["data"]["notes"],
            serde_json::json!([MISSING_REQUIRED_PRIMARY_LABEL_NOTE])
        );
        assert!(
            diagnostic.notes.is_empty(),
            "LSP projection should not mutate the stored diagnostic"
        );
    }

    #[test]
    fn diagnostic_with_primary_label_normalizes_public_label_contract() {
        let diagnostic =
            Diagnostic::error("LNC0016", "syntax error").with_primary_label(DiagnosticLabel {
                path: PathBuf::from("app.lani"),
                line: 0,
                column: 0,
                length: 0,
                byte_start: Some(12),
                byte_end: Some(8),
                source_line: None,
                message: " \t ".to_string(),
            });

        let label = diagnostic
            .primary_label
            .as_ref()
            .expect("diagnostic should carry a primary label");
        assert_eq!(label.line, 1);
        assert_eq!(label.column, 1);
        assert_eq!(label.length, 1);
        assert_eq!(label.byte_start, Some(12));
        assert_eq!(label.byte_end, Some(12));
        assert_eq!(label.message, DIAGNOSTIC_LABEL_MESSAGE_FALLBACK);

        let rendered = diagnostic.render();
        assert!(
            rendered.contains(" --> app.lani:1:1"),
            "text diagnostics should render one-based display coordinates\n{rendered}"
        );
        assert!(
            rendered.contains("     = relevant source location"),
            "text diagnostics should render a nonempty label message\n{rendered}"
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["primary_label"]["line"], 1);
        assert_eq!(value["primary_label"]["column"], 1);
        assert_eq!(value["primary_label"]["length"], 1);
        assert_eq!(value["primary_label"]["byte_start"], 12);
        assert_eq!(value["primary_label"]["byte_end"], 12);
        assert_eq!(
            value["primary_label"]["message"],
            DIAGNOSTIC_LABEL_MESSAGE_FALLBACK
        );

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("LSP diagnostic JSON should serialize");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert_eq!(lsp["range"]["start"]["line"], 0);
        assert_eq!(lsp["range"]["start"]["character"], 0);
        assert_eq!(lsp["range"]["end"]["line"], 0);
        assert_eq!(lsp["range"]["end"]["character"], 1);
        assert_eq!(
            lsp["data"]["primary_label"]["message"],
            DIAGNOSTIC_LABEL_MESSAGE_FALLBACK
        );
    }

    #[test]
    fn unsupported_feature_diagnostics_render_public_help_metadata() {
        let diagnostic = Diagnostic::error("LNC0022", "linked-output contract descriptor")
            .with_primary_label(DiagnosticLabel::primary(
                "linked-output.contract",
                1,
                1,
                1,
                None,
                "linked-output contract descriptor here",
            ))
            .with_note("descriptor payload contains Wasm module target bytes");

        let rendered = diagnostic.render();
        assert!(
            rendered.contains("= help:"),
            "text diagnostics should expose actionable help for unsupported boundaries\n{rendered}"
        );
        assert!(
            rendered.contains("target bytes"),
            "help should describe how to recover from descriptor/target-byte confusion\n{rendered}"
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("serialize diagnostic JSON");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["code"], "LNC0022");
        assert!(
            value["help"]
                .as_str()
                .expect("JSON diagnostic should include public help metadata")
                .contains("target bytes")
        );

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("serialize LSP diagnostic JSON");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert!(
            lsp["data"]["help"]
                .as_str()
                .expect("LSP diagnostic data should include public help metadata")
                .contains("target bytes")
        );
    }

    #[test]
    fn diagnostic_json_renderer_preserves_external_fields() {
        let diagnostic = Diagnostic::error("LNC0016", "syntax error")
            .with_primary_label(DiagnosticLabel::primary(
                "app.lani",
                2,
                5,
                2,
                Some("fn fn main() {}".to_string()),
                "invalid syntax here",
            ))
            .with_note("the source could not be parsed");

        let json = diagnostic
            .render_json_pretty()
            .expect("serialize diagnostic JSON");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");

        assert_eq!(value["schema_version"], DIAGNOSTIC_JSON_SCHEMA_VERSION);
        assert_eq!(value["schema_name"], DIAGNOSTIC_JSON_SCHEMA_NAME);
        assert_eq!(
            value["registry_schema_version"],
            DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
        );
        assert_eq!(value["severity"], "error");
        assert_eq!(value["code"], "LNC0016");
        assert_eq!(value["title"], "syntax error");
        assert_eq!(value["category"], "parsing");
        assert_eq!(value["primary_label_policy"], "required");
        assert_eq!(
            value["explain_command"],
            "laniusc diagnostics explain LNC0016"
        );
        assert_eq!(value["message"], "syntax error");
        assert_eq!(value["primary_label"]["path"], "app.lani");
        assert_eq!(value["primary_label"]["line"], 2);
        assert_eq!(value["primary_label"]["column"], 5);
        assert_eq!(value["primary_label"]["length"], 2);
        assert!(value["primary_label"]["byte_start"].is_null());
        assert!(value["primary_label"]["byte_end"].is_null());
        assert_eq!(value["primary_label"]["source_line"], "fn fn main() {}");
        assert_eq!(value["primary_label"]["message"], "invalid syntax here");
        assert_eq!(value["notes"][0], "the source could not be parsed");
    }

    #[test]
    fn diagnostic_lsp_renderer_uses_zero_based_utf16_ranges() {
        let diagnostic = Diagnostic::error("LNC0016", "syntax error").with_primary_label(
            DiagnosticLabel::primary(
                "app.lani",
                2,
                3,
                1,
                Some("a 💡 z".to_string()),
                "invalid syntax here",
            ),
        );

        let json = diagnostic
            .render_lsp_json_pretty()
            .expect("serialize LSP diagnostic JSON");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("LSP diagnostic JSON should parse");

        assert_eq!(value["severity"], LSP_DIAGNOSTIC_ERROR_SEVERITY);
        assert_eq!(value["code"], "LNC0016");
        assert_eq!(value["source"], LSP_DIAGNOSTIC_SOURCE);
        assert_eq!(value["message"], "syntax error");
        assert_eq!(
            value["data"]["registry_schema_version"],
            DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
        );
        assert_eq!(
            value["data"]["schema_version"],
            LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
        );
        assert_eq!(
            value["data"]["schema_name"],
            LSP_DIAGNOSTIC_DATA_SCHEMA_NAME
        );
        assert_eq!(value["data"]["position_encoding"], LSP_POSITION_ENCODING);
        assert_eq!(value["data"]["title"], "syntax error");
        assert_eq!(value["data"]["category"], "parsing");
        assert_eq!(value["data"]["primary_label_policy"], "required");
        assert_eq!(
            value["data"]["explain_command"],
            "laniusc diagnostics explain LNC0016"
        );
        assert!(value["data"]["primary_label"]["byte_start"].is_null());
        assert!(value["data"]["primary_label"]["byte_end"].is_null());
        assert_eq!(value["range"]["start"]["line"], 1);
        assert_eq!(value["range"]["start"]["character"], 2);
        assert_eq!(value["range"]["end"]["line"], 1);
        assert_eq!(value["range"]["end"]["character"], 4);
    }

    #[test]
    fn diagnostic_label_from_source_span_maps_bytes_to_line_column() {
        let label = diagnostic_label_from_source_span(
            "app.lani",
            "fn main() {\n    return later;\n}\n",
            23,
            5,
            "not found",
        );

        assert_eq!(label.path, PathBuf::from("app.lani"));
        assert_eq!(label.line, 2);
        assert_eq!(label.column, 12);
        assert_eq!(label.length, 5);
        assert_eq!(label.byte_start, Some(23));
        assert_eq!(label.byte_end, Some(28));
        assert_eq!(label.source_line, Some("    return later;".to_string()));
        assert_eq!(label.message, "not found");

        let diagnostic =
            Diagnostic::error("LNC0005", "unresolved identifier").with_primary_label(label);
        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["primary_label"]["byte_start"], 23);
        assert_eq!(value["primary_label"]["byte_end"], 28);

        let lsp_json = diagnostic
            .render_lsp_json_pretty()
            .expect("LSP diagnostic JSON should serialize");
        let lsp: serde_json::Value =
            serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
        assert_eq!(lsp["data"]["primary_label"]["byte_start"], 23);
        assert_eq!(lsp["data"]["primary_label"]["byte_end"], 28);
    }

    #[test]
    fn diagnostic_label_from_source_span_snaps_invalid_byte_spans_to_character_boundaries() {
        let source = "fn main() {\n    let café: i32 = 1;\n}\n";
        let cafe_byte = source
            .find("café")
            .expect("fixture should contain multibyte identifier");
        let invalid_start = cafe_byte + "caf".len() + 1;

        let label = diagnostic_label_from_source_span(
            "unicode.lani",
            source,
            invalid_start,
            1,
            "invalid syntax here",
        );

        assert_eq!(label.line, 2);
        assert_eq!(label.source_line.as_deref(), Some("    let café: i32 = 1;"));
        assert_eq!(
            label.column, 12,
            "label should snap to the start of the multibyte character"
        );
        assert_eq!(
            label.length, 1,
            "label should cover the multibyte character as one displayed column"
        );
        assert_eq!(label.byte_start, Some(cafe_byte + "caf".len()));
        assert_eq!(label.byte_end, Some(cafe_byte + "café".len()));
    }

    #[test]
    fn diagnostic_source_snippets_do_not_include_crlf_line_terminators() {
        let source = "fn main() {\r\n    return later;\r\n}\r\n";
        let start = source
            .find("later")
            .expect("test source contains label token");
        let diagnostic = Diagnostic::error("LNC0005", "unresolved identifier").with_primary_label(
            diagnostic_label_from_source_span(
                "app.lani",
                source,
                start,
                "later".len(),
                "unresolved identifier here",
            ),
        );

        let rendered = diagnostic.render();
        assert!(
            rendered.contains("2 |     return later;"),
            "text diagnostics should show the CRLF source line without its line terminator\n{rendered}"
        );
        assert!(
            !rendered.contains('\r'),
            "text diagnostics must not embed carriage returns from CRLF source lines\n{rendered:?}"
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("diagnostic JSON should serialize");
        let value: serde_json::Value =
            serde_json::from_str(&json).expect("diagnostic JSON should parse");
        assert_eq!(value["primary_label"]["line"], 2);
        assert_eq!(value["primary_label"]["source_line"], "    return later;");
    }
}
