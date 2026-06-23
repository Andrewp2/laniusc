use crate::{
    cli::common::{
        LANIUS_DEFAULT_EMIT_TARGET,
        LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_NAME,
        LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_NAME,
        LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_NAME,
        LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_NAME,
        LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_NAME,
        LANIUS_DISTRIBUTION_STATUS,
        LANIUS_EDITION_POLICY,
        LANIUS_EMIT_TARGETS,
        LANIUS_FORMATTER_CONTRACT,
        LANIUS_LANGUAGE_EDITION,
        LANIUS_LSP_CAPABILITIES_SCHEMA_NAME,
        LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION,
        LANIUS_LSP_ERROR_DATA_SCHEMA_NAME,
        LANIUS_LSP_ERROR_DATA_SCHEMA_VERSION,
        LANIUS_LSP_EXPERIMENTAL_SCHEMA_NAME,
        LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION,
        LANIUS_RELEASE_CHANNEL,
        LANIUS_TARGET_TRIPLES,
        LANIUS_X86_64_SUPPORT,
        formatter_policy_metadata,
    },
    compiler::{
        DIAGNOSTIC_EXPLANATION_SCHEMA_NAME,
        DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_VERSION,
        DIAGNOSTIC_REGISTRY_SCHEMA_VERSION,
    },
};

const VERSION_POLICY_SCHEMA_NAME: &str = "laniusc.diagnostics.version-policy";
const VERSION_POLICY_SCHEMA_VERSION: u32 = 6;
const COMMAND_DISCOVERY_SCHEMA_NAME: &str = "laniusc.diagnostics.command-discovery";
const COMMAND_DISCOVERY_SCHEMA_VERSION: u32 = 3;

/// Returns version, schema, target, and compatibility policy metadata.
pub(super) fn diagnostic_version_policy_json_pretty() -> Result<String, serde_json::Error> {
    let document = serde_json::json!({
        "schema_version": VERSION_POLICY_SCHEMA_VERSION,
        "schema_name": VERSION_POLICY_SCHEMA_NAME,
        "compiler": {
            "name": "laniusc",
            "package_version": env!("CARGO_PKG_VERSION"),
            "language_edition": LANIUS_LANGUAGE_EDITION,
            "edition_policy": LANIUS_EDITION_POLICY
        },
        "distribution": {
            "release_channel": LANIUS_RELEASE_CHANNEL,
            "status": LANIUS_DISTRIBUTION_STATUS,
            "production_release_claim": false,
            "stable_install_artifact": false,
            "package_manager_channel": false,
            "source_control_required_for_claims": true
        },
        "compatibility": {
            "machine_readable_contract": "schema_name and schema_version identify the JSON payload contract",
            "cli_version_text_contract": "human-readable summary; wrappers should prefer diagnostics version-policy",
            "language_edition_contract": "unstable-alpha only",
            "breaking_change_policy": "unstable-alpha worktree metadata may change until a stable production release policy exists"
        },
        "target_surface": {
            "emit_targets": LANIUS_EMIT_TARGETS,
            "default_emit_target": LANIUS_DEFAULT_EMIT_TARGET,
            "target_triples": LANIUS_TARGET_TRIPLES,
            "x86_64": LANIUS_X86_64_SUPPORT
        },
        "tooling": {
            "formatter": LANIUS_FORMATTER_CONTRACT,
            "formatter_policy": formatter_policy_metadata(),
            "diagnostic_registry_schema_version": DIAGNOSTIC_REGISTRY_SCHEMA_VERSION,
            "diagnostic_output_formats_schema_version": DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_VERSION,
            "lsp_capabilities_schema_name": LANIUS_LSP_CAPABILITIES_SCHEMA_NAME,
            "lsp_capabilities_schema_version": LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION,
            "lsp_experimental_schema_name": LANIUS_LSP_EXPERIMENTAL_SCHEMA_NAME,
            "lsp_experimental_schema_version": LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION,
            "lsp_error_data_schema_name": LANIUS_LSP_ERROR_DATA_SCHEMA_NAME,
            "lsp_error_data_schema_version": LANIUS_LSP_ERROR_DATA_SCHEMA_VERSION,
            "command_discovery": diagnostic_command_discovery_json()
        },
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "stdlib_source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false,
            "slangc_probe": false,
            "shader_loop_audit_execution": false,
            "pareas_invocation": false
        }
    });
    serde_json::to_string_pretty(&document)
}

/// Returns machine-readable discovery metadata for diagnostics subcommands.
pub(super) fn diagnostic_command_discovery_json_pretty() -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(&diagnostic_command_discovery_json())
}

/// Returns the formatter policy document shared by CLI and LSP surfaces.
pub(super) fn diagnostic_formatter_policy_json_pretty() -> Result<String, serde_json::Error> {
    serde_json::to_string_pretty(&formatter_policy_metadata())
}

fn diagnostic_command_discovery_json() -> serde_json::Value {
    let placeholders = vec![
        serde_json::json!({
            "placeholder": "CODE",
            "meaning": "stable diagnostic code selector",
            "accepted_selector_examples": [
                "LNC0018",
                "lnc0018",
                "error[LNC0018]: unsupported CLI option value"
            ],
            "bulk_discovery_command": "laniusc diagnostics codes",
            "used_by": [
                "laniusc diagnostics code CODE",
                "laniusc diagnostics explain CODE"
            ]
        }),
        serde_json::json!({
            "placeholder": "API",
            "meaning": "runtime-bound stdlib API selector",
            "accepted_selector_examples": [
                "std::io::print_i32",
                "stdio::print_i32",
                "\"std::io::print_i32\""
            ],
            "bulk_discovery_command": "laniusc diagnostics runtime-apis",
            "used_by": [
                "laniusc diagnostics runtime-api API"
            ]
        }),
        serde_json::json!({
            "placeholder": "SERVICE",
            "meaning": "runtime service selector",
            "accepted_selector_examples": [
                "stdio",
                "std::io",
                "STDIO_HAS_RUNTIME_BINDING",
                "stdio_service_status()",
                "std::io::print_i32"
            ],
            "bulk_discovery_command": "laniusc diagnostics runtime-services",
            "used_by": [
                "laniusc diagnostics runtime-service SERVICE",
                "laniusc diagnostics runtime-service-apis SERVICE"
            ]
        }),
        serde_json::json!({
            "placeholder": "DIR",
            "meaning": "persisted source-pack artifact root directory",
            "accepted_selector_examples": [
                ".lanius/source-pack",
                "/abs/path/to/source-pack-artifacts"
            ],
            "bulk_discovery_command": "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR",
            "used_by": [
                "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR"
            ]
        }),
    ];
    let selector_result_policies = vec![
        serde_json::json!({
            "placeholder": "CODE",
            "commands": [
                "laniusc diagnostics code CODE",
                "laniusc diagnostics explain CODE"
            ],
            "missing_selector_diagnostic_code": "LNC0026",
            "unknown_selector_behavior": "successful metadata query with known: false",
            "known_field": "known"
        }),
        serde_json::json!({
            "placeholder": "API",
            "commands": [
                "laniusc diagnostics runtime-api API"
            ],
            "missing_selector_diagnostic_code": "LNC0026",
            "unknown_selector_behavior": "successful metadata query with known: false",
            "known_field": "known"
        }),
        serde_json::json!({
            "placeholder": "SERVICE",
            "commands": [
                "laniusc diagnostics runtime-service SERVICE",
                "laniusc diagnostics runtime-service-apis SERVICE"
            ],
            "missing_selector_diagnostic_code": "LNC0026",
            "unknown_selector_behavior": "successful metadata query with known: false",
            "known_field": "known"
        }),
        serde_json::json!({
            "placeholder": "DIR",
            "commands": [
                "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR"
            ],
            "missing_selector_diagnostic_code": "LNC0023",
            "unknown_selector_behavior": "diagnostic with LNC0037 when the artifact record is missing or unreadable",
            "known_field": null
        }),
    ];
    let commands = vec![
        command_discovery_row(
            "laniusc diagnostics commands",
            COMMAND_DISCOVERY_SCHEMA_NAME,
            "no-run metadata command discovery without the broader version-policy envelope",
            None,
            "none",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics registry",
            "laniusc.diagnostics.registry",
            "full stable diagnostic registry for tools that need public metadata for every code",
            None,
            "none",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics codes",
            "laniusc.diagnostics.codes",
            "diagnostic code completion and filtering",
            None,
            "none",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics code CODE",
            "laniusc.diagnostics.code",
            "single diagnostic code lookup for detail panes and direct links",
            Some("CODE"),
            "selector",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics categories",
            "laniusc.diagnostics.categories",
            "diagnostic category grouping for filter-building tools",
            None,
            "none",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics formats",
            "laniusc.diagnostics.output-formats",
            "diagnostic renderer selection",
            None,
            "none",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics formatter",
            "laniusc.formatter.policy",
            "formatter policy, CLI commands, LSP request options, and no-run guard discovery",
            None,
            "none",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics version-policy",
            VERSION_POLICY_SCHEMA_NAME,
            "compiler version, edition, distribution, compatibility, target, and tooling schema policy",
            None,
            "none",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics explain CODE",
            DIAGNOSTIC_EXPLANATION_SCHEMA_NAME,
            "code-specific explanation and unsupported-boundary recovery guidance",
            Some("CODE"),
            "selector",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics runtime-api API",
            LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_NAME,
            "focused known runtime-bound stdlib API lookup",
            Some("API"),
            "selector",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics runtime-apis",
            LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_NAME,
            "known runtime-bound stdlib API discovery",
            None,
            "none",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics runtime-service SERVICE",
            LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_NAME,
            "focused runtime service boundary lookup",
            Some("SERVICE"),
            "selector",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics runtime-service-apis SERVICE",
            LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_NAME,
            "focused runtime service API listing",
            Some("SERVICE"),
            "selector",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics runtime-services",
            LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_NAME,
            "known runtime service boundary discovery",
            None,
            "none",
            false,
        ),
        command_discovery_row(
            "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR",
            "laniusc.diagnostics.source-pack-progress",
            "persisted source-pack work-queue progress inspection",
            Some("DIR"),
            "source-pack-artifact-root",
            true,
        ),
        command_discovery_row(
            "laniusc lsp capabilities",
            LANIUS_LSP_CAPABILITIES_SCHEMA_NAME,
            "editor capability and protocol contract discovery",
            None,
            "none",
            false,
        ),
        command_discovery_row(
            "laniusc doctor --skip-slangc-probe",
            "laniusc.doctor.report",
            "local install/readiness metadata without compiling source or launching Slang",
            None,
            "toolchain-metadata",
            false,
        ),
    ];
    let placeholder_count = placeholders.len();
    let selector_policy_count = selector_result_policies.len();
    let command_count = commands.len();
    serde_json::json!({
        "schema_version": COMMAND_DISCOVERY_SCHEMA_VERSION,
        "schema_name": COMMAND_DISCOVERY_SCHEMA_NAME,
        "policy": "wrappers should use these machine-readable metadata commands instead of scraping --help text",
        "preferred_policy_command": "laniusc diagnostics version-policy",
        "command_index_command": "laniusc diagnostics commands",
        "human_help_command": "laniusc --help",
        "placeholder_policy": "uppercase words in command rows are user-supplied arguments; use placeholder rows to build focused lookup UIs and completion",
        "placeholder_count": placeholder_count,
        "placeholders": placeholders,
        "selector_policy_count": selector_policy_count,
        "selector_result_policies": selector_result_policies,
        "command_count": command_count,
        "commands": commands,
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "stdlib_source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false,
            "slangc_probe": false,
            "shader_loop_audit_execution": false,
            "pareas_invocation": false
        }
    })
}

fn command_discovery_row(
    command: &str,
    schema_name: &str,
    purpose: &str,
    selector_placeholder: Option<&str>,
    input_kind: &str,
    artifact_input: bool,
) -> serde_json::Value {
    serde_json::json!({
        "command": command,
        "schema_name": schema_name,
        "purpose": purpose,
        "selector_placeholder": selector_placeholder,
        "input_kind": input_kind,
        "source_input": false,
        "artifact_input": artifact_input,
        "no_run_boundary": "metadata query; source compilation, source scanning, GPU device creation, and target codegen are false in no_run_guards"
    })
}
