use std::env;

use super::{
    super::{
        common::{
            CliError,
            LANIUS_DEFAULT_EMIT_TARGET,
            LANIUS_DISTRIBUTION_STATUS,
            LANIUS_DOCTOR_SCHEMA_VERSION,
            LANIUS_EDITION_POLICY,
            LANIUS_LANGUAGE_EDITION,
            LANIUS_RELEASE_CHANNEL,
            LANIUS_X86_64_SUPPORT,
        },
        lsp,
    },
    slangc,
};
use crate::{
    compiler::{
        LSP_DIAGNOSTIC_SOURCE,
        LSP_POSITION_ENCODING,
        RUNTIME_BOUND_API_DIAGNOSTICS,
        RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS,
        diagnostic_output_formats,
        diagnostic_registry,
    },
    shader_artifacts,
};

const LANGUAGE_SLICE_INVENTORY_PATH: &str = "docs/language_slice_unstable_alpha.tsv";
const LANGUAGE_SLICE_INVENTORY_GATE: &str =
    "tools/compiler_acceptance.sh --tier readiness --check-plan";

pub(super) fn json_pretty(skip_slangc_probe: bool) -> Result<String, CliError> {
    let (slangc_status, slangc_check) = if skip_slangc_probe {
        ("skipped", slangc::skipped_probe())
    } else {
        slangc::check()
    };
    let diagnostic_registry_schema_version = diagnostic_registry().schema_version;
    let diagnostic_format_registry = diagnostic_output_formats();
    let shader_digest = shader_artifacts::digest();
    let shader_count = shader_artifacts::count();
    let shader_max_spv_bytes = shader_artifacts::max_spv_bytes();
    let shader_max_spv_name = shader_artifacts::max_spv_name();
    let shader_size_guard_status = shader_artifacts::size_guard_status();
    let shader_size_guard_max_bytes = shader_artifacts::size_guard_max_bytes_text();
    let status = match slangc_status {
        "ok" => "ok",
        "skipped" => "not-checked",
        _ => "action-required",
    };
    let document = serde_json::json!({
        "schema_version": LANIUS_DOCTOR_SCHEMA_VERSION,
        "status": status,
        "compiler": {
            "name": "laniusc",
            "version": env!("CARGO_PKG_VERSION"),
            "language_edition": LANIUS_LANGUAGE_EDITION,
            "edition_policy": LANIUS_EDITION_POLICY,
            "emit_targets": ["x86_64", "wasm"],
            "default_emit_target": LANIUS_DEFAULT_EMIT_TARGET,
            "target_triples": ["x86_64-unknown-linux-gnu", "wasm32-unknown-unknown"],
            "x86_64": LANIUS_X86_64_SUPPORT,
        },
        "distribution": {
            "release_channel": LANIUS_RELEASE_CHANNEL,
            "status": LANIUS_DISTRIBUTION_STATUS,
            "stable_install_artifact": false,
            "package_manager_channel": false,
            "release_artifact_workflow": false,
            "source_control_required_for_claims": true,
            "production_release_claim": false,
            "next_user_gate": "install from a published artifact, create a package, format it, get editor diagnostics, compile, and run native output"
        },
        "toolchain": {
            "slangc": slangc_check,
            "wgpu": {
                "status": known_or_unknown_status(option_env!("LANIUS_WGPU_VERSION")),
                "version": option_env!("LANIUS_WGPU_VERSION").unwrap_or("unknown"),
            },
            "build_profile": {
                "status": known_or_unknown_status(option_env!("LANIUS_BUILD_PROFILE")),
                "value": option_env!("LANIUS_BUILD_PROFILE").unwrap_or("unknown"),
            },
            "shader_artifacts": {
                "digest": {
                    "status": known_or_unknown_status(Some(shader_digest.as_str())),
                    "value": shader_digest,
                },
                "count": shader_artifact_u64_metadata(shader_count),
                "largest": {
                    "status": known_or_unknown_status(shader_max_spv_bytes.map(|_| "known")),
                    "name": shader_max_spv_name,
                    "bytes": shader_artifact_u64_metadata(shader_max_spv_bytes),
                },
                "size_guard": {
                    "status": shader_size_guard_status,
                    "max_spv_bytes": shader_artifact_guard_max_metadata(&shader_size_guard_max_bytes),
                    "policy": "active SPIR-V artifacts must stay below the build-time cap; LANIUS_SHADER_MAX_SPV_BYTES=0 disables the guard only for local investigation",
                },
            },
            "build_timeouts": {
            "slangc_version_probe_ms": build_timeout_metadata(option_env!("LANIUS_SLANGC_VERSION_TIMEOUT_MS")),
            "shader_compile_ms": build_timeout_metadata(option_env!("LANIUS_SHADER_COMPILE_TIMEOUT_MS")),
            "policy": "build-time Slang subprocesses are time-bounded by default; set the matching timeout env var to 0 only for local investigation; laniusc doctor --skip-slangc-probe skips the runtime Slang availability subprocess for metadata-only wrappers",
            "env": {
                "slangc_version_probe_ms": "LANIUS_SLANGC_VERSION_TIMEOUT_MS",
                "shader_compile_ms": "LANIUS_SHADER_COMPILE_TIMEOUT_MS"
                }
            },
        },
        "diagnostics": {
            "cli_flag": diagnostic_format_registry.cli_flag,
            "default_format": diagnostic_format_registry.default_format,
            "accepted_formats": diagnostic_format_registry.accepted_formats,
            "registry_schema_version": diagnostic_registry_schema_version,
            "formats_schema_version": diagnostic_format_registry.schema_version,
            "lsp_source": LSP_DIAGNOSTIC_SOURCE,
            "lsp_position_encoding": LSP_POSITION_ENCODING,
            "lsp_error_data": lsp::error_data_contract_metadata(),
        },
        "readiness": {
            "status": "not-production-ready",
            "default_no_run_gate": LANGUAGE_SLICE_INVENTORY_GATE,
            "default_no_run_gate_compiles_tests": false,
            "default_no_run_gate_creates_gpu_device": false,
            "default_no_run_gate_invokes_pareas": false,
            "test_discipline": {
                "schema_name": "laniusc.readiness.test-discipline",
                "schema_version": 1,
                "inventory_gate": LANGUAGE_SLICE_INVENTORY_GATE,
                "inventory_gate_compiles_tests": false,
                "inventory_gate_executes_tests": false,
                "named_filter_existence_check": true,
                "duplicate_same_lane_references_rejected": true,
                "rust_integration_test_audit": true,
                "compiler_shader_product_source_inspection": "rejected",
                "source_scoped_evidence_policy": "public-boundary-artifact-contract-execution-contract-or-measurement-scaffold-only"
            },
            "generated_scale_lane": "opt-in",
            "pareas_lane": "opt-in",
            "performance_claims": "local-artifacts-required",
            "paper_numbers": "reference-only-not-local-performance-evidence",
            "claim_requirements": [
                "supported language slice evidence",
                "object/interface/partial-link artifacts",
                "claimable pass contracts",
                "local timing/readback/VRAM artifacts",
                "source-control provenance",
                "repeatability"
            ]
        },
        "pass_contracts": {
            "status": "blocked",
            "loop_policy": "scale-claims-require-unbounded-pass-loops",
            "fallback_status": "fail-closed",
            "claim_status": "blocked",
            "paper_alignment_policy": "paper-and-pareas-pass-shape-required",
            "audit_command": "tools/shader_loop_audit.sh --summary-only",
            "paper_pass_blocker_gate": "tools/shader_loop_audit.sh --summary-only --fail-on-paper-pass-blocker",
            "source_sized_symbolic_cap_gate": "tools/shader_loop_audit.sh --summary-only --fail-on-source-sized-symbolic-cap",
            "audit_executed_by_doctor": false,
            "claim_boundary": "metadata-only-no-run-not-performance-evidence",
            "expected_gpu_primitives": [
                "record-publication",
                "prefix-scan",
                "segmented-scan",
                "sort-join",
                "scatter",
                "reduction"
            ],
            "source_sized_symbolic_caps": "claim-blockers-until-justified-or-rewritten"
        },
        "language_slice": {
            "edition": LANIUS_LANGUAGE_EDITION,
            "status": "bounded-unstable-alpha",
            "inventory_path": LANGUAGE_SLICE_INVENTORY_PATH,
            "inventory_gate": LANGUAGE_SLICE_INVENTORY_GATE,
            "inventory_checked_by_doctor": false,
            "supported_statuses": ["supported", "bounded"],
            "non_support_statuses": ["planned", "unsupported"],
            "evidence_contracts": [
                "public-boundary",
                "artifact-contract",
                "record-invariant",
                "semantic-contract",
                "execution-contract",
                "fail-closed-diagnostic",
                "measurement-scaffold"
            ],
            "production_release_claim": false,
            "policy": "supported and bounded rows require behavior-facing evidence; planned and unsupported rows are explicit non-support"
        },
        "stdlib": {
            "status": "explicit-root-required",
            "cli_flag": "--stdlib-root",
            "suggested_root": "stdlib",
            "auto_imported": false,
            "source_rewrite": false,
            "module_loading": "leading module/import declarations are loaded into the GPU source-pack resolver from explicit roots",
            "runtime_bound_status": "known-unbound-contracts",
            "executable_host_apis": false,
            "runtime_boundary_diagnostic_code": "LNC0038",
            "runtime_boundary_explain_command": "laniusc diagnostics explain LNC0038",
            "runtime_service_boundary_count": RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.len(),
            "runtime_bound_api_count": RUNTIME_BOUND_API_DIAGNOSTICS.len(),
            "runtime_boundary_detail": "use diagnostics explain LNC0038, diagnostics runtime-apis, or diagnostics runtime-services for row-level runtime boundary metadata",
            "layers": [
                {
                    "name": "core",
                    "current_status": "source-seed",
                    "host_runtime_required": false,
                    "auto_imported": false
                },
                {
                    "name": "alloc",
                    "current_status": "source-contract",
                    "host_runtime_required": true,
                    "auto_imported": false
                },
                {
                    "name": "std",
                    "current_status": "runtime-contract",
                    "host_runtime_required": true,
                    "auto_imported": false
                },
                {
                    "name": "test",
                    "current_status": "runtime-contract",
                    "host_runtime_required": true,
                    "auto_imported": false
                }
            ]
        },
        "no_run_guards": {
            "source_compilation": false,
            "language_slice_inventory_validation": false,
            "stdlib_source_scanning": false,
            "shader_loop_audit_execution": false,
            "target_codegen": false,
            "gpu_device_creation": false,
            "readiness_gate_execution": false,
            "pareas_invocation": false,
            "generated_workloads": false,
            "slangc_probe": !skip_slangc_probe,
            "note": "doctor reports local toolchain, language-slice, readiness, pass-contract, and stdlib boundary metadata only; it does not validate the language-slice inventory, scan stdlib source, run shader loop audits, compile source, run target codegen, create a GPU device, execute readiness gates, run generated gates, or invoke Pareas; --skip-slangc-probe also avoids the runtime Slang availability subprocess"
        }
    });
    serde_json::to_string_pretty(&document)
        .map_err(|err| format!("serialize doctor report: {err}").into())
}

fn shader_artifact_u64_metadata(value: Option<u64>) -> serde_json::Value {
    value.map_or_else(|| serde_json::json!("unknown"), serde_json::Value::from)
}

fn shader_artifact_guard_max_metadata(value: &str) -> serde_json::Value {
    match value {
        "disabled" => serde_json::json!("disabled"),
        value => value
            .parse::<u64>()
            .map_or_else(|_| serde_json::json!("unknown"), serde_json::Value::from),
    }
}

fn build_timeout_metadata(value: Option<&str>) -> serde_json::Value {
    match value {
        Some("disabled") => serde_json::json!("disabled"),
        Some(value) => value
            .parse::<u64>()
            .map_or_else(|_| serde_json::json!("unknown"), serde_json::Value::from),
        None => serde_json::json!("unknown"),
    }
}

fn known_or_unknown_status(value: Option<&str>) -> &'static str {
    match value {
        Some(value) if !value.trim().is_empty() && value != "unknown" => "ok",
        _ => "unknown",
    }
}
