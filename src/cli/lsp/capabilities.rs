use laniusc::compiler::{
    LSP_DIAGNOSTIC_SOURCE,
    LSP_POSITION_ENCODING,
    diagnostic_output_formats,
    diagnostic_registry,
};

use super::{LSP_LANGUAGE_ID, protocol};
use crate::cli::common::{
    LANIUS_DISTRIBUTION_STATUS,
    LANIUS_FORMATTER_CONTRACT,
    LANIUS_LSP_CAPABILITIES_SCHEMA_NAME,
    LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION,
    LANIUS_LSP_EXPERIMENTAL_SCHEMA_NAME,
    LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION,
    LANIUS_RELEASE_CHANNEL,
    LSP_POST_SHUTDOWN_METHODS,
    LSP_PRE_INITIALIZE_METHODS,
    LSP_STDIO_METHODS,
    formatter_policy_metadata,
};

pub(super) fn capabilities_document() -> serde_json::Value {
    serde_json::json!({
        "schema_name": LANIUS_LSP_CAPABILITIES_SCHEMA_NAME,
        "schema_version": LANIUS_LSP_CAPABILITIES_SCHEMA_VERSION,
        "status": "stdio-handshake-ready",
        "server": {
            "name": "laniusc",
            "version": env!("CARGO_PKG_VERSION"),
            "stdio": true,
            "stdio_methods": LSP_STDIO_METHODS
        },
        "language_id": LSP_LANGUAGE_ID,
        "position_encoding": LSP_POSITION_ENCODING,
        "diagnostic_source": LSP_DIAGNOSTIC_SOURCE,
        "diagnostic_registry": diagnostic_registry(),
        "diagnostic_formats": diagnostic_output_formats(),
        "distribution": distribution_metadata(),
        "transport": protocol::transport_contract_metadata(),
        "error_data": protocol::error_data_contract_metadata(),
        "document_sync": {
            "open_close": true,
            "change": 1,
            "change_kind": "full",
            "incremental_changes": false
        },
        "workspace": workspace_metadata(),
        "formatting": formatter_metadata(),
        "lifecycle": lifecycle_metadata(),
        "document_diagnostics": document_diagnostics_metadata(),
        "claim_boundaries": claim_boundaries_metadata(),
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    })
}

pub(super) fn initialize_response(id: serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "jsonrpc": "2.0",
        "id": id,
        "result": {
            "serverInfo": {
                "name": "laniusc",
                "version": env!("CARGO_PKG_VERSION")
            },
            "capabilities": {
                "positionEncoding": LSP_POSITION_ENCODING,
                "textDocumentSync": {
                    "openClose": true,
                    "change": 1
                },
                "diagnosticProvider": {
                    "interFileDependencies": false,
                    "workspaceDiagnostics": false
                },
                "documentFormattingProvider": true,
                "workspaceSymbolProvider": false,
                "workspace": {
                    "workspaceFolders": {
                        "supported": false,
                        "changeNotifications": false
                    }
                },
                "experimental": {
                    "laniusc": {
                        "schema_name": LANIUS_LSP_EXPERIMENTAL_SCHEMA_NAME,
                        "schema_version": LANIUS_LSP_EXPERIMENTAL_SCHEMA_VERSION,
                        "language_id": LSP_LANGUAGE_ID,
                        "diagnostic_source": LSP_DIAGNOSTIC_SOURCE,
                        "diagnostic_registry": diagnostic_registry(),
                        "diagnostic_formats": diagnostic_output_formats(),
                        "distribution": distribution_metadata(),
                        "transport": protocol::transport_contract_metadata(),
                        "error_data": protocol::error_data_contract_metadata(),
                        "workspace": workspace_metadata(),
                        "formatting": formatter_metadata(),
                        "lifecycle": lifecycle_metadata(),
                        "supported_methods": LSP_STDIO_METHODS,
                        "document_diagnostics": true,
                        "document_diagnostics_metadata": document_diagnostics_metadata(),
                        "claim_boundaries": claim_boundaries_metadata(),
                        "no_run_guards": {
                            "source_compilation": false,
                            "source_scanning": false,
                            "gpu_device_creation": false,
                            "target_codegen": false
                        }
                    }
                }
            }
        }
    })
}

fn distribution_metadata() -> serde_json::Value {
    serde_json::json!({
        "release_channel": LANIUS_RELEASE_CHANNEL,
        "status": LANIUS_DISTRIBUTION_STATUS,
        "stable_install_artifact": false,
        "package_manager_channel": false,
        "release_artifact_workflow": false,
        "source_control_required_for_claims": true,
        "production_release_claim": false
    })
}

fn workspace_metadata() -> serde_json::Value {
    serde_json::json!({
        "workspace_folders": false,
        "workspace_folder_changes": false,
        "workspace_symbol_provider": false,
        "configuration_requests": false,
        "file_operations": false,
        "workspace_diagnostics": false,
        "source_root_loading": false,
        "stdlib_root_loading": false,
        "open_document_scope": "explicit textDocument/didOpen documents only",
        "initialize_root_uri": "ignored",
        "initialize_workspace_folders": "ignored"
    })
}

fn lifecycle_metadata() -> serde_json::Value {
    serde_json::json!({
        "pre_initialize_allowed_methods": LSP_PRE_INITIALIZE_METHODS,
        "post_shutdown_allowed_methods": LSP_POST_SHUTDOWN_METHODS,
        "repeated_initialize_rejected": true,
        "repeated_initialize_preserves_session": true,
        "stateful_notifications_before_initialize": "ignored",
        "stateful_notifications_after_shutdown": "ignored"
    })
}

fn formatter_metadata() -> serde_json::Value {
    serde_json::json!({
        "policy": formatter_policy_metadata(),
        "document_formatting_provider": true,
        "method": "textDocument/formatting",
        "edit_strategy": "single full-document replacement when formatting changes",
        "range_formatting_provider": false,
        "request_options": {
            "params_options_required": true,
            "tab_size_lsp_field": "tabSize",
            "tab_size": 4,
            "insert_spaces_lsp_field": "insertSpaces",
            "insert_spaces": true,
            "additional_options": "ignored"
        },
        "cli_command": "laniusc fmt --stdin",
        "cli_check_command": "laniusc fmt --stdin --check",
        "formatter_contract": LANIUS_FORMATTER_CONTRACT,
        "source_compilation": false,
        "source_scanning": false,
        "gpu_device_creation": false,
        "target_codegen": false
    })
}

fn document_diagnostics_metadata() -> serde_json::Value {
    serde_json::json!({
        "method": "textDocument/diagnostic",
        "provider_kind": "pull",
        "report_kind": "full",
        "document_scope": "open-document-text",
        "publish_diagnostics": false,
        "inter_file_dependencies": false,
        "workspace_diagnostics": false,
        "result_id_supported": false,
        "source_scanning": false,
        "source_root_loading": false,
        "stdlib_root_loading": false,
        "source_compilation": true,
        "gpu_device_creation": true,
        "target_codegen": false
    })
}

fn claim_boundaries_metadata() -> serde_json::Value {
    serde_json::json!({
        "schema_name": "laniusc.lsp.claim-boundaries",
        "schema_version": 1,
        "evidence_kind": "public-boundary-metadata",
        "claim_boundary": "stdio protocol metadata and single-open-document pull diagnostics only",
        "capabilities_are_performance_evidence": false,
        "capabilities_are_production_readiness_claim": false,
        "production_editor_ready": false,
        "workspace_claim_status": "not-supported",
        "latency_claim_status": "not-measured",
        "throughput_claim_status": "not-measured",
        "local_performance_claim_status": "not-claimable",
        "measurement_evidence_policy": "local-artifacts-only; capabilities metadata is not performance evidence",
        "required_performance_evidence": "local LSP latency/responsiveness artifacts separate from lanius.measurement-summary.v1 compiler throughput artifacts",
        "claim_blockers": [
            "no workspace diagnostics",
            "no source-root loading",
            "no stdlib-root loading",
            "no local LSP latency artifacts",
            "not a release artifact"
        ],
        "no_run_guards": {
            "source_compilation": false,
            "source_scanning": false,
            "gpu_device_creation": false,
            "target_codegen": false
        }
    })
}
