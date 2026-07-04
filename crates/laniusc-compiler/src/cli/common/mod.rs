mod args;
mod constants;
mod diagnostic_format;
mod error;
mod numbers;
mod package;
mod paths;

pub(crate) use args::cli_args_without_diagnostic_format;
pub(crate) use constants::{
    LANIUS_DEFAULT_EMIT_TARGET,
    LANIUS_DIAGNOSTIC_CATEGORIES_SCHEMA_VERSION,
    LANIUS_DIAGNOSTIC_CODES_SCHEMA_VERSION,
    LANIUS_DIAGNOSTIC_FORMATS,
    LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_NAME,
    LANIUS_DIAGNOSTIC_RUNTIME_API_SCHEMA_VERSION,
    LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_NAME,
    LANIUS_DIAGNOSTIC_RUNTIME_APIS_SCHEMA_VERSION,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_NAME,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_APIS_SCHEMA_VERSION,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_NAME,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICE_SCHEMA_VERSION,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_NAME,
    LANIUS_DIAGNOSTIC_RUNTIME_SERVICES_SCHEMA_VERSION,
    LANIUS_DISTRIBUTION_STATUS,
    LANIUS_DOCTOR_SCHEMA_VERSION,
    LANIUS_EDITION_POLICY,
    LANIUS_EMIT_TARGETS,
    LANIUS_FORMATTER_CONTRACT,
    LANIUS_FORMATTER_POLICY_SCHEMA_NAME,
    LANIUS_FORMATTER_POLICY_SCHEMA_VERSION,
    LANIUS_LANGUAGE_EDITION,
    LANIUS_LSP_CAPABILITIES_SCHEMA_NAME,
    LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION,
    LANIUS_LSP_ERROR_DATA_SCHEMA_NAME,
    LANIUS_LSP_ERROR_DATA_SCHEMA_VERSION,
    LANIUS_LSP_EXPERIMENTAL_SCHEMA_NAME,
    LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION,
    LANIUS_LSP_INTERNAL_ERROR_CODE,
    LANIUS_LSP_INVALID_PARAMS_ERROR_CODE,
    LANIUS_LSP_INVALID_REQUEST_ERROR_CODE,
    LANIUS_LSP_METHOD_NOT_FOUND_ERROR_CODE,
    LANIUS_LSP_PARSE_ERROR_CODE,
    LANIUS_LSP_SERVER_NOT_INITIALIZED_ERROR_CODE,
    LANIUS_RELEASE_CHANNEL,
    LANIUS_SOURCE_PACK_PROGRESS_SCHEMA_VERSION,
    LANIUS_TARGET_TRIPLES,
    LANIUS_X86_64_SUPPORT,
    LSP_POST_SHUTDOWN_METHODS,
    LSP_PRE_INITIALIZE_METHODS,
    LSP_STDIO_METHODS,
};
pub(crate) use diagnostic_format::{
    DiagnosticFormat,
    diagnostic_format_from_args,
    validate_diagnostic_format,
};
pub(crate) use error::{
    CliError,
    explicit_source_pack_manifest_invalid_error,
    extra_cli_argument_error,
    incompatible_cli_options_error,
    invalid_cli_argument_count_error,
    invalid_cli_directory_path_error,
    missing_cli_argument_error,
    missing_cli_option_value_error,
    missing_cli_subcommand_error,
    source_pack_artifact_store_cli_error,
    unknown_cli_option_error,
    unknown_cli_subcommand_error,
    unsupported_cli_option_value_error,
};
pub(crate) use numbers::parse_usize_value;
pub(crate) use package::{package_compile_cli_error, package_metadata_cli_error};
pub(crate) use paths::{canonical_directory_path, canonical_unique_directory_paths};

/// Returns the LSP JSON-RPC error-data contract metadata.
pub(crate) fn lsp_error_data_metadata() -> serde_json::Value {
    serde_json::json!({
        "schema_name": LANIUS_LSP_ERROR_DATA_SCHEMA_NAME,
        "schema_version": LANIUS_LSP_ERROR_DATA_SCHEMA_VERSION,
        "transport": "json-rpc-error-data",
        "diagnostic_field": "diagnostic",
        "supported_methods_field": "supported_methods",
        "no_run_guards_field": "no_run_guards",
        "json_rpc_error_codes": {
            "parse_error": LANIUS_LSP_PARSE_ERROR_CODE,
            "invalid_request": LANIUS_LSP_INVALID_REQUEST_ERROR_CODE,
            "method_not_found": LANIUS_LSP_METHOD_NOT_FOUND_ERROR_CODE,
            "invalid_params": LANIUS_LSP_INVALID_PARAMS_ERROR_CODE,
            "internal_error": LANIUS_LSP_INTERNAL_ERROR_CODE,
            "server_not_initialized": LANIUS_LSP_SERVER_NOT_INITIALIZED_ERROR_CODE
        },
        "diagnostic_codes": {
            "unsupported_method": "LNC0028",
            "invalid_message": "LNC0029"
        }
    })
}

/// Returns the formatter policy metadata shared by diagnostics and LSP output.
pub(crate) fn formatter_policy_metadata() -> serde_json::Value {
    serde_json::json!({
        "schema_name": LANIUS_FORMATTER_POLICY_SCHEMA_NAME,
        "schema_version": LANIUS_FORMATTER_POLICY_SCHEMA_VERSION,
        "formatter_contract": LANIUS_FORMATTER_CONTRACT,
        "stability": "unstable-alpha",
        "formatter_kind": "lexical",
        "document_scope": "full-document",
        "range_formatting": false,
        "syntax_parsing": false,
        "type_checking": false,
        "import_resolution": false,
        "semantic_rewrites": false,
        "token_preservation": "preserves non-whitespace token text and token order; rewrites whitespace, newlines, and indentation only",
        "line_endings": "lf",
        "indent": {
            "style": "spaces",
            "size": 4
        },
        "cli": {
            "format_stdin": "laniusc fmt --stdin",
            "check_stdin": "laniusc fmt --stdin --check",
            "format_files": "laniusc fmt <input.lani>...",
            "check_files": "laniusc fmt --check <input.lani>..."
        },
        "lsp": {
            "method": "textDocument/formatting",
            "edit_strategy": "single full-document replacement when formatting changes",
            "request_options": {
                "params_options_required": true,
                "tab_size_lsp_field": "tabSize",
                "tab_size": 4,
                "insert_spaces_lsp_field": "insertSpaces",
                "insert_spaces": true,
                "additional_options": "ignored"
            }
        },
        "diagnostic_codes": {
            "check_failed": "LNC0019",
            "input_read_failed": "LNC0040",
            "output_write_failed": "LNC0034",
            "output_stream_failed": "LNC0035"
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
    })
}
