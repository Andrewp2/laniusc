mod common;

use std::{
    fs,
    io::{self, Write},
    path::PathBuf,
    process::{Child, Command, Output, Stdio},
    thread,
    time::{Duration, Instant},
};

use laniusc::{
    codegen::unit::SourcePackArtifactTarget,
    compiler::{
        FilesystemArtifactStore,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE,
        SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        SourcePackBuildState,
        SourcePackHierarchicalLinkExecutionIndex,
        SourcePackWorkQueueProgressIndex,
    },
};

const CLI_DIAGNOSTIC_TIMEOUT: Duration = Duration::from_secs(30);
const CHILD_PROCESS_POLL_INTERVAL: Duration = Duration::from_millis(2);

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

fn json_string_array<'a>(value: &'a serde_json::Value, field: &str) -> Vec<&'a str> {
    value[field]
        .as_array()
        .unwrap_or_else(|| panic!("{field} should be an array"))
        .iter()
        .map(|entry| {
            entry
                .as_str()
                .unwrap_or_else(|| panic!("{field} entries should be strings"))
        })
        .collect()
}

fn json_string_array_matches(value: &serde_json::Value, field: &str, expected: &[&str]) -> bool {
    json_string_array(value, field).as_slice() == expected
}

#[test]
fn diagnostic_registry_json_contains_code_metadata_categories_and_unsupported_boundaries() {
    let json = laniusc::compiler::diagnostic_registry_json_pretty()
        .expect("diagnostic registry should serialize");
    let registry: serde_json::Value =
        serde_json::from_str(&json).expect("diagnostic registry JSON should parse");

    assert_eq!(
        registry["schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(
        registry["schema_name"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_NAME
    );
    assert_eq!(registry["no_run_guards"]["source_compilation"], false);
    assert_eq!(registry["no_run_guards"]["source_scanning"], false);
    assert_eq!(registry["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(registry["no_run_guards"]["target_codegen"], false);

    let codes = registry["codes"]
        .as_array()
        .expect("registry codes should be an array");
    let first_code = codes.first().expect("registry should contain diagnostics");
    assert_eq!(first_code["code"], "LNC0001");
    assert_eq!(first_code["title"], "missing source-root module");
    assert_eq!(first_code["category"], "package/import loading");
    assert_eq!(first_code["primary_label_policy"], "required");
    assert_eq!(first_code["default_severity"], "error");
    assert_eq!(first_code["lsp_source"], "laniusc");
    assert_eq!(first_code["lsp_severity"], 1);
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0017"
            && code["title"] == "x86 backend boundary"
            && code["category"] == "native codegen"
            && code["primary_label_policy"] == "required"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0018"
            && code["title"] == "unsupported CLI option value"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0019"
            && code["title"] == "formatter check failed"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "required"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0020"
            && code["title"] == "unknown CLI option"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0022"
            && code["title"] == "linked-output contract descriptor"
            && code["category"] == "native codegen"
            && code["primary_label_policy"] == "required"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0023"
            && code["title"] == "missing CLI option value"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0025"
            && code["title"] == "missing CLI subcommand"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0026"
            && code["title"] == "missing CLI argument"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0027"
            && code["title"] == "call resolution failed"
            && code["category"] == "type checking"
            && code["primary_label_policy"] == "required"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0028"
            && code["title"] == "unsupported LSP method"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0031"
            && code["title"] == "unexpected CLI argument"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0032"
            && code["title"] == "incompatible CLI options"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0034"
            && code["title"] == "output write failed"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "required"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0035"
            && code["title"] == "output stream write failed"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0036"
            && code["title"] == "WASM backend boundary"
            && code["category"] == "target codegen"
            && code["primary_label_policy"] == "required"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0037"
            && code["title"] == "package metadata invalid"
            && code["category"] == "package/import loading"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0038"
            && code["title"] == "runtime service boundary"
            && code["category"] == "runtime binding"
            && code["primary_label_policy"] == "required"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0039"
            && code["title"] == "unknown CLI subcommand"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0040"
            && code["title"] == "input read failed"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "required"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
    }));

    let categories = registry["categories"]
        .as_array()
        .expect("registry categories should be an array")
        .iter()
        .map(|category| {
            category
                .as_str()
                .expect("registry category should be a string")
        })
        .collect::<Vec<_>>();
    assert!(categories.contains(&"module resolution"));
    assert!(categories.contains(&"native codegen"));
    assert!(categories.contains(&"runtime binding"));
    assert!(categories.contains(&"target codegen"));
    assert!(categories.contains(&"tooling"));
    assert!(categories.contains(&"type checking"));

    let unsupported_features = registry["unsupported_features"]
        .as_array()
        .expect("unsupported feature registry should be an array");
    assert!(unsupported_features.iter().any(|feature| {
        feature["code"] == "LNC0017"
            && feature["boundary"] == "x86 backend"
            && feature["summary"]
                .as_str()
                .expect("unsupported feature summary should be a string")
                .contains("native-codegen")
            && feature["next_step"]
                .as_str()
                .expect("unsupported feature next_step should be a string")
                .contains("--emit=wasm")
    }));
    assert!(unsupported_features.iter().any(|feature| {
        feature["code"] == "LNC0022"
            && feature["boundary"] == "linked-output contract descriptor"
            && feature["summary"]
                .as_str()
                .expect("unsupported feature summary should be a string")
                .contains("JSON contract metadata")
            && feature["next_step"]
                .as_str()
                .expect("unsupported feature next_step should be a string")
                .contains("target bytes")
    }));
    assert!(unsupported_features.iter().any(|feature| {
        feature["code"] == "LNC0036"
            && feature["boundary"] == "WASM backend"
            && feature["summary"]
                .as_str()
                .expect("unsupported feature summary should be a string")
                .contains("WASM-codegen")
            && feature["next_step"]
                .as_str()
                .expect("unsupported feature next_step should be a string")
                .contains("laniusc check")
    }));
    assert!(unsupported_features.iter().any(|feature| {
        feature["code"] == "LNC0024"
            && feature["boundary"] == "source-root package boundary"
            && feature["summary"]
                .as_str()
                .expect("unsupported feature summary should be a string")
                .contains("package/user source roots")
            && feature["next_step"]
                .as_str()
                .expect("unsupported feature next_step should be a string")
                .contains("package manifest/lockfile metadata")
    }));
    assert!(unsupported_features.iter().any(|feature| {
        feature["code"] == "LNC0038"
            && feature["boundary"] == "runtime service binding"
            && feature["summary"]
                .as_str()
                .expect("unsupported feature summary should be a string")
                .contains("runtime service descriptor")
            && !feature["next_step"]
                .as_str()
                .expect("unsupported feature next_step should be a string")
                .trim()
                .is_empty()
    }));
}

#[test]
fn diagnostic_explain_describes_source_root_package_boundary_recovery() {
    let json = laniusc::compiler::diagnostic_explanation_json_pretty("lnc0024")
        .expect("diagnostic explanation should serialize");
    let explanation: serde_json::Value =
        serde_json::from_str(&json).expect("diagnostic explanation JSON should parse");

    assert_eq!(explanation["requested_code"], "LNC0024");
    assert_eq!(
        explanation["schema_name"],
        laniusc::compiler::DIAGNOSTIC_EXPLANATION_SCHEMA_NAME
    );
    assert_eq!(explanation["known"], true);
    assert_eq!(explanation["diagnostic"]["code"], "LNC0024");
    assert_eq!(
        explanation["diagnostic"]["category"],
        "package/import loading"
    );
    assert_eq!(
        explanation["unsupported_feature"]["boundary"],
        "source-root package boundary"
    );
    assert!(
        explanation["unsupported_feature"]["summary"]
            .as_str()
            .expect("boundary summary should be public text")
            .contains("stdlib roots")
    );
    assert!(
        explanation["unsupported_feature"]["next_step"]
            .as_str()
            .expect("boundary next step should be public text")
            .contains("package manifest/lockfile metadata")
    );
}

#[test]
fn diagnostic_explain_describes_runtime_service_boundary_recovery() {
    let json = laniusc::compiler::diagnostic_explanation_json_pretty("lnc0038")
        .expect("diagnostic explanation should serialize");
    let explanation: serde_json::Value =
        serde_json::from_str(&json).expect("diagnostic explanation JSON should parse");

    assert_eq!(explanation["requested_code"], "LNC0038");
    assert_eq!(
        explanation["schema_name"],
        laniusc::compiler::DIAGNOSTIC_EXPLANATION_SCHEMA_NAME
    );
    assert_eq!(explanation["known"], true);
    assert_eq!(explanation["diagnostic"]["code"], "LNC0038");
    assert_eq!(explanation["diagnostic"]["category"], "runtime binding");
    assert_eq!(
        explanation["unsupported_feature"]["boundary"],
        "runtime service binding"
    );
    assert!(
        explanation["unsupported_feature"]["summary"]
            .as_str()
            .expect("boundary summary should be public text")
            .contains("known but not bound")
    );
    assert!(
        !explanation["unsupported_feature"]["next_step"]
            .as_str()
            .expect("boundary next step should be public text")
            .trim()
            .is_empty()
    );
    let runtime_services = explanation["runtime_service_boundaries"]
        .as_array()
        .expect("runtime service boundary explanation should include service rows");
    assert_eq!(
        runtime_services.len(),
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.len()
    );
    assert!(runtime_services.iter().any(|service| {
        service["diagnostic_code"] == "LNC0038"
            && service["service_id"].as_u64()
                == Some(u64::from(
                    laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
                ))
            && service["service_name"] == "stdio"
            && service["module_path"] == "std::io"
            && service["binding_probe"]
                .as_str()
                .is_some_and(|probe| !probe.trim().is_empty())
            && json_string_array_matches(
                service,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
            )
            && service["current_status"] == "known-unbound"
            && service["executable"] == false
    }));
    assert!(runtime_services.iter().all(|service| {
        service["diagnostic_code"] == "LNC0038"
            && service["current_status"] == "known-unbound"
            && service["executable"] == false
    }));
    let runtime_apis = explanation["runtime_bound_apis"]
        .as_array()
        .expect("runtime service boundary explanation should include API rows");
    assert_eq!(
        runtime_apis.len(),
        laniusc::compiler::RUNTIME_BOUND_API_DIAGNOSTICS.len()
    );
    assert!(runtime_apis.iter().any(|api| {
        api["diagnostic_code"] == "LNC0038"
            && api["service_id"].as_u64()
                == Some(u64::from(
                    laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
                ))
            && api["module_path"] == "std::io"
            && api["api_name"] == "std::io::print_i32"
            && api["service_module_path"] == "std::io"
            && api["service_current_status"] == "known-unbound"
            && api["service_executable"] == false
            && api["binding_probe"]
                .as_str()
                .is_some_and(|probe| !probe.trim().is_empty())
            && json_string_array_matches(
                api,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
            )
            && api["current_status"] == "known-unbound"
            && api["executable"] == false
    }));
    assert!(runtime_apis.iter().all(|api| {
        let service_id = api["service_id"]
            .as_u64()
            .and_then(|service_id| u32::try_from(service_id).ok());
        let service =
            service_id.and_then(laniusc::compiler::runtime_service_boundary_diagnostic_info);
        api["diagnostic_code"] == "LNC0038"
            && api["current_status"] == "known-unbound"
            && api["executable"] == false
            && service.is_some_and(|service| {
                api["service_capability_constant"] == service.capability_constant
                    && api["service_module_path"] == service.module_path
                    && api["service_status_probe"] == service.status_probe
                    && api["service_binding_probe"] == service.binding_probe
                    && api["service_current_status"] == service.current_status
                    && api["service_executable"] == service.executable
            })
    }));
}

#[test]
fn diagnostic_output_formats_json_describes_cli_payload_contracts() {
    let json = laniusc::compiler::diagnostic_output_formats_json_pretty()
        .expect("diagnostic output formats should serialize");
    let registry: serde_json::Value =
        serde_json::from_str(&json).expect("diagnostic output format JSON should parse");

    assert_eq!(
        registry["schema_version"],
        laniusc::compiler::DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_VERSION
    );
    assert_eq!(
        registry["schema_name"],
        laniusc::compiler::DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_NAME
    );
    assert_eq!(registry["cli_flag"], "--diagnostic-format");
    assert_eq!(registry["default_format"], "text");
    assert_eq!(
        registry["accepted_formats"]
            .as_array()
            .expect("accepted diagnostic formats should be an array")
            .iter()
            .map(|format| format
                .as_str()
                .expect("accepted diagnostic format should be a string"))
            .collect::<Vec<_>>(),
        vec!["text", "json", "lsp-json"]
    );
    assert_eq!(registry["no_run_guards"]["source_compilation"], false);
    assert_eq!(registry["no_run_guards"]["source_scanning"], false);
    assert_eq!(registry["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(registry["no_run_guards"]["target_codegen"], false);

    let formats = registry["formats"]
        .as_array()
        .expect("diagnostic formats should be an array");
    for format in formats {
        let description = format["description"]
            .as_str()
            .expect("diagnostic format description should be a string");
        assert!(
            !description.trim().is_empty(),
            "diagnostic format rows should keep a human-readable description"
        );
    }
    let names = formats
        .iter()
        .map(|format| {
            format["name"]
                .as_str()
                .expect("diagnostic format name should be a string")
        })
        .collect::<Vec<_>>();
    assert_eq!(names, vec!["text", "json", "lsp-json"]);

    let json_format = formats
        .iter()
        .find(|format| format["name"] == "json")
        .expect("JSON diagnostic format should be listed");
    assert_eq!(json_format["output_stream"], "stderr");
    assert_eq!(json_format["payload"], "Diagnostic JSON object");
    assert_eq!(
        json_format["payload_schema_name"],
        laniusc::compiler::DIAGNOSTIC_JSON_SCHEMA_NAME
    );
    assert_eq!(
        json_format["payload_schema_version"],
        laniusc::compiler::DIAGNOSTIC_JSON_SCHEMA_VERSION
    );
    assert_eq!(json_format["payload_schema_location"], "top-level");
    assert_eq!(
        json_format["position_encoding"],
        "one-based source line and column"
    );
    assert_eq!(json_format["includes_source_snippet"], true);
    assert_eq!(json_format["language_server_envelope"], false);
    assert_eq!(json_format["check_mode_supported"], true);
    assert_eq!(json_format["formatter_check_supported"], true);

    let lsp_json_format = formats
        .iter()
        .find(|format| format["name"] == "lsp-json")
        .expect("LSP JSON diagnostic format should be listed");
    assert_eq!(lsp_json_format["output_stream"], "stderr");
    assert_eq!(lsp_json_format["payload"], "LSP Diagnostic JSON object");
    assert_eq!(
        lsp_json_format["payload_schema_name"],
        laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_NAME
    );
    assert_eq!(
        lsp_json_format["payload_schema_version"],
        laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
    );
    assert_eq!(lsp_json_format["payload_schema_location"], "data");
    assert_eq!(lsp_json_format["position_encoding"], "utf-16");
    assert_eq!(lsp_json_format["includes_source_snippet"], false);
    assert_eq!(lsp_json_format["language_server_envelope"], false);
    assert_eq!(lsp_json_format["check_mode_supported"], true);
    assert_eq!(lsp_json_format["formatter_check_supported"], true);
}

#[test]
fn diagnostic_output_formats_json_keeps_selector_rows_in_sync_for_wrappers() {
    let json = laniusc::compiler::diagnostic_output_formats_json_pretty()
        .expect("diagnostic output formats should serialize");
    let registry: serde_json::Value =
        serde_json::from_str(&json).expect("diagnostic output format JSON should parse");

    let accepted_formats = registry["accepted_formats"]
        .as_array()
        .expect("accepted diagnostic formats should be an array");
    let mut accepted_names = std::collections::BTreeSet::new();
    for format in accepted_formats {
        let name = format
            .as_str()
            .expect("accepted diagnostic format should be a string");
        assert!(
            accepted_names.insert(name.to_string()),
            "accepted diagnostic format names should be unique"
        );
    }

    let formats = registry["formats"]
        .as_array()
        .expect("diagnostic formats should be an array");
    let mut row_names = std::collections::BTreeSet::new();
    for format in formats {
        let name = format["name"]
            .as_str()
            .expect("diagnostic format row name should be a string");
        assert!(
            accepted_names.contains(name),
            "diagnostic format row {name} should be an accepted selector"
        );
        assert!(
            row_names.insert(name.to_string()),
            "diagnostic format row {name} should appear once"
        );
        assert_eq!(format["output_stream"], "stderr");
        assert_eq!(format["language_server_envelope"], false);
        assert_eq!(format["check_mode_supported"], true);
        assert_eq!(format["formatter_check_supported"], true);
        if name == "text" {
            assert!(
                format["payload_schema_name"].is_null()
                    && format["payload_schema_version"].is_null()
                    && format["payload_schema_location"].is_null(),
                "text diagnostics should not claim a machine-readable payload schema"
            );
        } else {
            assert!(
                format["payload_schema_name"]
                    .as_str()
                    .is_some_and(|schema| schema.starts_with("laniusc.diagnostics.")),
                "machine-readable diagnostic format {name} should publish a payload schema name"
            );
            assert!(
                format["payload_schema_version"]
                    .as_u64()
                    .is_some_and(|version| version > 0),
                "machine-readable diagnostic format {name} should publish a payload schema version"
            );
            assert!(
                matches!(
                    format["payload_schema_location"].as_str(),
                    Some("top-level") | Some("data")
                ),
                "machine-readable diagnostic format {name} should publish where the schema appears"
            );
        }
    }

    assert_eq!(
        row_names, accepted_names,
        "diagnostic format metadata rows should cover every accepted selector"
    );
}

#[test]
fn cli_diagnostics_registry_prints_combined_registry_json_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command.arg("diagnostics").arg("registry");
    let output = command_output_with_timeout(
        "laniusc diagnostics registry",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics registry");

    assert!(
        output.status.success(),
        "diagnostics registry should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics registry should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let registry: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("registry output should be JSON");
    assert_eq!(
        registry["schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(
        registry["schema_name"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_NAME
    );
    assert_eq!(registry["no_run_guards"]["source_compilation"], false);
    assert_eq!(registry["no_run_guards"]["source_scanning"], false);
    assert_eq!(registry["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(registry["no_run_guards"]["target_codegen"], false);
    assert!(
        registry["codes"]
            .as_array()
            .expect("registry codes should be an array")
            .iter()
            .any(|code| {
                code["code"] == "LNC0016"
                    && code["category"] == "parsing"
                    && code["primary_label_policy"] == "required"
                    && code["lsp_source"] == "laniusc"
            }),
        "registry command should expose stable compiler diagnostic code metadata\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        registry["codes"]
            .as_array()
            .expect("registry codes should be an array")
            .iter()
            .any(|code| {
                code["code"] == "LNC0033"
                    && code["title"] == "invalid generic parameter list"
                    && code["category"] == "type checking"
                    && code["primary_label_policy"] == "required"
                    && code["lsp_source"] == "laniusc"
                    && code["lsp_severity"] == 1
            }),
        "registry command should expose the generic-parameter diagnostic code\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        registry["codes"]
            .as_array()
            .expect("registry codes should be an array")
            .iter()
            .any(|code| {
                code["code"] == "LNC0034"
                    && code["title"] == "output write failed"
                    && code["category"] == "tooling"
                    && code["primary_label_policy"] == "required"
            }),
        "registry command should expose the output-write diagnostic code\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        registry["codes"]
            .as_array()
            .expect("registry codes should be an array")
            .iter()
            .any(|code| {
                code["code"] == "LNC0035"
                    && code["title"] == "output stream write failed"
                    && code["category"] == "tooling"
                    && code["primary_label_policy"] == "none"
            }),
        "registry command should expose the output-stream diagnostic code\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        registry["codes"]
            .as_array()
            .expect("registry codes should be an array")
            .iter()
            .any(|code| {
                code["code"] == "LNC0038"
                    && code["title"] == "runtime service boundary"
                    && code["category"] == "runtime binding"
                    && code["primary_label_policy"] == "required"
            }),
        "registry command should expose the runtime-service diagnostic code\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        registry["unsupported_features"]
            .as_array()
            .expect("unsupported features should be an array")
            .iter()
            .any(|feature| {
                feature["code"] == "LNC0017"
                    && feature["boundary"] == "x86 backend"
                    && feature["next_step"]
                        .as_str()
                        .is_some_and(|next_step| next_step.contains("--emit=wasm"))
            }),
        "registry command should expose unsupported boundary metadata\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        registry["unsupported_features"]
            .as_array()
            .expect("unsupported features should be an array")
            .iter()
            .any(|feature| {
                feature["code"] == "LNC0022"
                    && feature["boundary"] == "linked-output contract descriptor"
            }),
        "registry command should expose descriptor contract boundary metadata\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        registry["unsupported_features"]
            .as_array()
            .expect("unsupported features should be an array")
            .iter()
            .any(|feature| {
                feature["code"] == "LNC0038"
                    && feature["boundary"] == "runtime service binding"
                    && feature["next_step"]
                        .as_str()
                        .is_some_and(|next_step| !next_step.trim().is_empty())
            }),
        "registry command should expose runtime-service boundary metadata\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let codegen_boundaries = registry["codegen_boundaries"]
        .as_array()
        .expect("registry should expose codegen boundary rows");
    assert!(
        codegen_boundaries.iter().any(|boundary| {
            boundary["diagnostic_code"] == "LNC0017"
                && boundary["boundary"] == "x86 backend"
                && boundary["target"] == "x86_64"
                && boundary["stage"] == "native codegen lowering"
                && boundary["target_bytes_emitted"] == false
                && boundary["diagnostics_only_command"] == "laniusc check"
                && boundary["fallback_emit"] == "wasm"
        }),
        "registry command should expose x86 fail-closed codegen boundary metadata\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        codegen_boundaries.iter().any(|boundary| {
            boundary["diagnostic_code"] == "LNC0036"
                && boundary["boundary"] == "WASM backend"
                && boundary["target"] == "wasm"
                && boundary["stage"] == "WASM codegen lowering"
                && boundary["partial_artifact_policy"]
                    == "fail-closed before emitting a partial module prefix"
                && boundary["target_bytes_emitted"] == false
                && boundary["diagnostics_only_command"] == "laniusc check"
                && boundary["fallback_emit"].is_null()
        }),
        "registry command should expose WASM fail-closed codegen boundary metadata\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
}

#[test]
fn cli_diagnostics_codes_prints_compact_code_index_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command.arg("diagnostics").arg("codes");
    let output = command_output_with_timeout(
        "laniusc diagnostics codes",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics codes");

    assert!(
        output.status.success(),
        "diagnostics codes should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics codes should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("code index output should be JSON");
    assert_eq!(document["schema_version"], 2);
    assert_eq!(document["schema_name"], "laniusc.diagnostics.codes");
    assert_eq!(
        document["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    let codes = document["codes"]
        .as_array()
        .expect("code index should include code rows");
    assert_eq!(document["code_count"], codes.len());
    assert!(document.get("unsupported_features").is_none());
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0018"
            && code["title"] == "unsupported CLI option value"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
            && code["explain_command"] == "laniusc diagnostics explain LNC0018"
    }));
    let lnc0018_index_row = codes
        .iter()
        .find(|code| code["code"] == "LNC0018")
        .expect("code index should include LNC0018");
    assert!(codes.iter().any(|code| {
        code["code"] == "LNC0038"
            && code["title"] == "runtime service boundary"
            && code["category"] == "runtime binding"
            && code["primary_label_policy"] == "required"
            && code["explain_command"] == "laniusc diagnostics explain LNC0038"
    }));

    let mut code_command = Command::new(laniusc_bin());
    code_command
        .arg("diagnostics")
        .arg("code")
        .arg("error[LNC0018]: unsupported CLI option value")
        .arg("--diagnostic-format=json");
    let code_output = command_output_with_timeout(
        "laniusc diagnostics code copied selector",
        &mut code_command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics code");

    assert!(
        code_output.status.success(),
        "diagnostics code should succeed for a copied public selector\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&code_output.stdout),
        String::from_utf8_lossy(&code_output.stderr)
    );
    assert!(
        code_output.stderr.is_empty(),
        "diagnostics code should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&code_output.stderr)
    );

    let code_document: serde_json::Value =
        serde_json::from_slice(&code_output.stdout).expect("code lookup output should be JSON");
    assert_eq!(code_document["schema_version"], 2);
    assert_eq!(code_document["schema_name"], "laniusc.diagnostics.code");
    assert_eq!(
        code_document["registry_schema_version"],
        document["registry_schema_version"]
    );
    assert_eq!(code_document["requested_code"], "LNC0018");
    assert_eq!(code_document["known"], true);
    assert_eq!(&code_document["diagnostic"], lnc0018_index_row);
    assert_eq!(
        code_document["explain_command"],
        "laniusc diagnostics explain LNC0018"
    );
    assert_eq!(
        code_document["code_index_command"],
        "laniusc diagnostics codes"
    );
    assert_eq!(
        code_document["registry_command"],
        "laniusc diagnostics registry"
    );
    assert_eq!(code_document["no_run_guards"], document["no_run_guards"]);
    let examples = json_string_array(&code_document, "accepted_selector_examples");
    assert!(
        examples.contains(&"LNC0018")
            && examples.contains(&"lnc0018")
            && examples
                .iter()
                .any(|example| example.contains("error[LNC0018]")),
        "focused code lookup should publish selector examples\nstdout:\n{}",
        String::from_utf8_lossy(&code_output.stdout)
    );
    let patterns = json_string_array(&code_document, "accepted_selector_patterns");
    assert!(
        patterns.iter().any(|pattern| pattern.contains("LNCdddd"))
            && patterns
                .iter()
                .any(|pattern| pattern.contains("copied text")),
        "focused code lookup should publish selector patterns\nstdout:\n{}",
        String::from_utf8_lossy(&code_output.stdout)
    );
}

#[test]
fn cli_diagnostics_codes_is_registry_projection_without_source_loading() {
    let mut registry_command = Command::new(laniusc_bin());
    registry_command
        .arg("diagnostics")
        .arg("registry")
        .arg("--diagnostic-format=json");
    let registry_output = command_output_with_timeout(
        "laniusc diagnostics registry JSON projection source",
        &mut registry_command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics registry");
    assert!(
        registry_output.status.success(),
        "diagnostics registry should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&registry_output.stdout),
        String::from_utf8_lossy(&registry_output.stderr)
    );
    assert!(
        registry_output.stderr.is_empty(),
        "diagnostics registry should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&registry_output.stderr)
    );

    let mut codes_command = Command::new(laniusc_bin());
    codes_command
        .arg("diagnostics")
        .arg("codes")
        .arg("--diagnostic-format=json");
    let codes_output = command_output_with_timeout(
        "laniusc diagnostics codes JSON projection",
        &mut codes_command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics codes");
    assert!(
        codes_output.status.success(),
        "diagnostics codes should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&codes_output.stdout),
        String::from_utf8_lossy(&codes_output.stderr)
    );
    assert!(
        codes_output.stderr.is_empty(),
        "diagnostics codes should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&codes_output.stderr)
    );

    let registry: serde_json::Value =
        serde_json::from_slice(&registry_output.stdout).expect("registry output should be JSON");
    let code_index: serde_json::Value =
        serde_json::from_slice(&codes_output.stdout).expect("code index output should be JSON");
    assert_eq!(
        code_index["registry_schema_version"], registry["schema_version"],
        "code index should identify the registry schema it projects"
    );
    assert_eq!(
        code_index["schema_name"], "laniusc.diagnostics.codes",
        "code index should publish a stable payload identity"
    );
    assert!(
        code_index.get("unsupported_features").is_none(),
        "code index should stay a compact code projection, not duplicate boundary guidance"
    );
    assert_eq!(code_index["no_run_guards"], registry["no_run_guards"]);

    let projected_fields = [
        "title",
        "category",
        "primary_label_policy",
        "default_severity",
        "lsp_source",
        "lsp_severity",
    ];
    let mut registry_rows = std::collections::BTreeMap::new();
    for row in registry["codes"]
        .as_array()
        .expect("registry codes should be an array")
    {
        let code = row["code"]
            .as_str()
            .expect("registry code should be a string")
            .to_string();
        let projected = projected_fields
            .iter()
            .map(|field| ((*field).to_string(), row[*field].clone()))
            .collect::<std::collections::BTreeMap<_, _>>();
        assert!(
            registry_rows.insert(code.clone(), projected).is_none(),
            "registry should not contain duplicate diagnostic code {code}"
        );
    }

    let code_rows = code_index["codes"]
        .as_array()
        .expect("code index should include code rows");
    assert_eq!(code_index["code_count"], code_rows.len());
    for row in code_rows {
        let code = row["code"]
            .as_str()
            .expect("code index code should be a string");
        let expected = registry_rows
            .remove(code)
            .unwrap_or_else(|| panic!("code index included {code} outside registry"));
        for field in projected_fields {
            assert_eq!(
                row.get(field)
                    .unwrap_or_else(|| panic!("code index row for {code} omitted {field}")),
                expected
                    .get(field)
                    .unwrap_or_else(|| panic!("registry row for {code} omitted {field}")),
                "code index field {field} should match registry row for {code}"
            );
        }
        assert_eq!(
            row["explain_command"],
            format!("laniusc diagnostics explain {code}"),
            "code index should publish a direct explain command for {code}"
        );
    }
    assert!(
        registry_rows.is_empty(),
        "code index omitted registry codes: {:?}",
        registry_rows.keys().collect::<Vec<_>>()
    );
}

#[test]
fn cli_diagnostics_code_unknown_result_includes_discovery_guidance_without_source_loading() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("code")
        .arg("not-a-code")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics code unknown selector",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics code");

    assert!(
        output.status.success(),
        "unknown diagnostic code lookup should remain a successful metadata query\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "unknown diagnostic code lookup should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("code lookup output should be JSON");
    assert_eq!(document["schema_version"], 2);
    assert_eq!(document["schema_name"], "laniusc.diagnostics.code");
    assert_eq!(
        document["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(document["requested_code"], "NOT-A-CODE");
    assert_eq!(document["known"], false);
    assert!(document["diagnostic"].is_null());
    assert_eq!(
        document["explain_command"],
        "laniusc diagnostics explain NOT-A-CODE"
    );
    assert_eq!(document["code_index_command"], "laniusc diagnostics codes");
    assert_eq!(document["registry_command"], "laniusc diagnostics registry");

    let examples = json_string_array(&document, "accepted_selector_examples");
    assert!(
        examples.contains(&"LNC0018") && examples.contains(&"lnc0018"),
        "code lookup should publish direct code selector examples\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(
        examples
            .iter()
            .any(|example| example.contains("error[LNC0018]")),
        "code lookup should publish copied diagnostic selector examples\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let patterns = json_string_array(&document, "accepted_selector_patterns");
    assert!(
        patterns.iter().any(|pattern| pattern.contains("LNCdddd"))
            && patterns
                .iter()
                .any(|pattern| pattern.contains("copied text")),
        "code lookup should describe accepted selector patterns\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
}

#[test]
fn cli_diagnostics_categories_is_registry_projection_without_source_loading() {
    let mut registry_command = Command::new(laniusc_bin());
    registry_command
        .arg("diagnostics")
        .arg("registry")
        .arg("--diagnostic-format=json");
    let registry_output = command_output_with_timeout(
        "laniusc diagnostics registry JSON category projection source",
        &mut registry_command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics registry");
    assert!(
        registry_output.status.success(),
        "diagnostics registry should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&registry_output.stdout),
        String::from_utf8_lossy(&registry_output.stderr)
    );
    assert!(
        registry_output.stderr.is_empty(),
        "diagnostics registry should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&registry_output.stderr)
    );

    let mut categories_command = Command::new(laniusc_bin());
    categories_command
        .arg("diagnostics")
        .arg("categories")
        .arg("--diagnostic-format=json");
    let categories_output = command_output_with_timeout(
        "laniusc diagnostics categories JSON projection",
        &mut categories_command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics categories");
    assert!(
        categories_output.status.success(),
        "diagnostics categories should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&categories_output.stdout),
        String::from_utf8_lossy(&categories_output.stderr)
    );
    assert!(
        categories_output.stderr.is_empty(),
        "diagnostics categories should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&categories_output.stderr)
    );

    let registry: serde_json::Value =
        serde_json::from_slice(&registry_output.stdout).expect("registry output should be JSON");
    let category_index: serde_json::Value = serde_json::from_slice(&categories_output.stdout)
        .expect("category index output should be JSON");
    assert_eq!(
        category_index["registry_schema_version"], registry["schema_version"],
        "category index should identify the registry schema it projects"
    );
    assert_eq!(
        category_index["schema_name"], "laniusc.diagnostics.categories",
        "category index should publish a stable payload identity"
    );
    assert_eq!(category_index["no_run_guards"], registry["no_run_guards"]);

    let projected_fields = [
        "title",
        "category",
        "primary_label_policy",
        "default_severity",
        "lsp_source",
        "lsp_severity",
    ];
    let mut code_categories = std::collections::BTreeMap::new();
    let mut registry_rows_by_category: std::collections::BTreeMap<
        String,
        std::collections::BTreeMap<String, std::collections::BTreeMap<String, serde_json::Value>>,
    > = std::collections::BTreeMap::new();
    for row in registry["codes"]
        .as_array()
        .expect("registry codes should be an array")
    {
        let code = row["code"]
            .as_str()
            .expect("registry code should be a string")
            .to_string();
        let category = row["category"]
            .as_str()
            .expect("registry code category should be a string")
            .to_string();
        assert!(
            code_categories
                .insert(code.clone(), category.clone())
                .is_none(),
            "registry should not contain duplicate diagnostic code {code}"
        );
        let projected = projected_fields
            .iter()
            .map(|field| ((*field).to_string(), row[*field].clone()))
            .collect::<std::collections::BTreeMap<_, _>>();
        assert!(
            registry_rows_by_category
                .entry(category)
                .or_default()
                .insert(code.clone(), projected)
                .is_none(),
            "registry category projection should not duplicate {code}"
        );
    }

    let registry_categories = registry["categories"]
        .as_array()
        .expect("registry categories should be an array")
        .iter()
        .map(|category| {
            category
                .as_str()
                .expect("registry category should be a string")
                .to_string()
        })
        .collect::<Vec<_>>();
    let category_rows = category_index["categories"]
        .as_array()
        .expect("category index should include category rows");
    assert_eq!(
        category_index["category_count"],
        category_rows.len(),
        "category index should publish the top-level category row count"
    );
    assert_eq!(
        category_rows.len(),
        registry_categories.len(),
        "category index should include every registry category once"
    );

    let mut seen_categories = std::collections::BTreeSet::new();
    let mut seen_category_order = Vec::new();
    let mut seen_codes = std::collections::BTreeSet::new();
    for category_row in category_rows {
        let category = category_row["name"]
            .as_str()
            .expect("category row name should be a string");
        assert!(
            registry_categories.iter().any(|name| name == category),
            "category index included {category:?} outside registry categories"
        );
        assert!(
            seen_categories.insert(category.to_string()),
            "category index should not duplicate category {category:?}"
        );
        seen_category_order.push(category.to_string());

        let code_rows = category_row["codes"]
            .as_array()
            .expect("category row should include code rows");
        assert_eq!(
            category_row["code_count"],
            code_rows.len(),
            "category {category} code_count should match code row count"
        );
        for row in code_rows {
            let code = row["code"]
                .as_str()
                .expect("category code row code should be a string");
            assert!(
                seen_codes.insert(code.to_string()),
                "category index should not list diagnostic code {code} more than once"
            );
            assert_eq!(
                row["category"], category,
                "category index row for {code} should stay in its named category"
            );
            let expected = registry_rows_by_category
                .get_mut(category)
                .and_then(|rows| rows.remove(code))
                .unwrap_or_else(|| {
                    panic!("category index included {code} outside registry category {category}")
                });
            for field in projected_fields {
                assert_eq!(
                    row.get(field)
                        .unwrap_or_else(|| panic!("category row for {code} omitted {field}")),
                    expected
                        .get(field)
                        .unwrap_or_else(|| panic!("registry row for {code} omitted {field}")),
                    "category index field {field} should match registry row for {code}"
                );
            }
            assert_eq!(
                row["explain_command"],
                format!("laniusc diagnostics explain {code}"),
                "category index should publish a direct explain command for {code}"
            );
        }

        let expected_unsupported_feature_codes = registry["unsupported_features"]
            .as_array()
            .expect("registry unsupported features should be an array")
            .iter()
            .filter_map(|feature| {
                let code = feature["code"]
                    .as_str()
                    .expect("unsupported feature code should be a string");
                code_categories
                    .get(code)
                    .is_some_and(|feature_category| feature_category == category)
                    .then_some(code)
            })
            .collect::<Vec<_>>();
        assert_eq!(
            json_string_array(category_row, "unsupported_feature_codes"),
            expected_unsupported_feature_codes,
            "category {category} unsupported feature codes should project registry metadata"
        );
    }

    assert_eq!(
        seen_category_order, registry_categories,
        "category index should preserve registry category order"
    );
    assert!(
        registry_rows_by_category
            .values()
            .all(|rows| rows.is_empty()),
        "category index omitted registry rows: {:?}",
        registry_rows_by_category
            .iter()
            .filter_map(|(category, rows)| (!rows.is_empty()).then_some((category, rows.keys())))
            .collect::<Vec<_>>()
    );
    assert_eq!(
        seen_codes,
        code_categories.keys().cloned().collect(),
        "category index should cover every registry diagnostic code exactly once"
    );
}

#[test]
fn cli_diagnostics_categories_groups_codes_by_stable_category_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("categories")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics categories",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics categories");

    assert!(
        output.status.success(),
        "diagnostics categories should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics categories should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("categories output should be JSON");
    assert_eq!(document["schema_version"], 4);
    assert_eq!(document["schema_name"], "laniusc.diagnostics.categories");
    assert_eq!(
        document["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);

    let categories = document["categories"]
        .as_array()
        .expect("categories should be an array");
    assert_eq!(document["category_count"], categories.len());
    let names = categories
        .iter()
        .map(|category| {
            category["name"]
                .as_str()
                .expect("category name should be a string")
        })
        .collect::<Vec<_>>();
    assert_eq!(
        names,
        vec![
            "module resolution",
            "name resolution",
            "native codegen",
            "package/import loading",
            "parsing",
            "runtime binding",
            "target codegen",
            "tooling",
            "trait solving",
            "type checking"
        ]
    );

    let tooling = categories
        .iter()
        .find(|category| category["name"] == "tooling")
        .expect("tooling category should be present");
    let tooling_codes = tooling["codes"]
        .as_array()
        .expect("tooling codes should be an array");
    assert_eq!(tooling["code_count"], tooling_codes.len());
    assert!(tooling_codes.iter().any(|code| {
        code["code"] == "LNC0018"
            && code["category"] == "tooling"
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
            && code["explain_command"] == "laniusc diagnostics explain LNC0018"
    }));
    assert!(tooling_codes.iter().any(|code| {
        code["code"] == "LNC0034"
            && code["title"] == "output write failed"
            && code["primary_label_policy"] == "required"
    }));
    assert!(tooling_codes.iter().any(|code| {
        code["code"] == "LNC0035"
            && code["title"] == "output stream write failed"
            && code["primary_label_policy"] == "none"
    }));

    let native_codegen = categories
        .iter()
        .find(|category| category["name"] == "native codegen")
        .expect("native codegen category should be present");
    let unsupported_feature_codes = native_codegen["unsupported_feature_codes"]
        .as_array()
        .expect("unsupported feature codes should be an array");
    assert!(
        unsupported_feature_codes
            .iter()
            .any(|code| code == "LNC0017")
    );
    assert!(
        unsupported_feature_codes
            .iter()
            .any(|code| code == "LNC0022")
    );

    let target_codegen = categories
        .iter()
        .find(|category| category["name"] == "target codegen")
        .expect("target codegen category should be present");
    let target_unsupported_feature_codes = target_codegen["unsupported_feature_codes"]
        .as_array()
        .expect("target codegen unsupported feature codes should be an array");
    assert!(
        target_unsupported_feature_codes
            .iter()
            .any(|code| code == "LNC0036")
    );

    let runtime_binding = categories
        .iter()
        .find(|category| category["name"] == "runtime binding")
        .expect("runtime binding category should be present");
    assert!(
        runtime_binding["codes"]
            .as_array()
            .expect("runtime binding codes should be an array")
            .iter()
            .any(|code| {
                code["code"] == "LNC0038"
                    && code["title"] == "runtime service boundary"
                    && code["primary_label_policy"] == "required"
            })
    );
    let runtime_unsupported_feature_codes = runtime_binding["unsupported_feature_codes"]
        .as_array()
        .expect("runtime binding unsupported feature codes should be an array");
    assert!(
        runtime_unsupported_feature_codes
            .iter()
            .any(|code| code == "LNC0038")
    );

    let package_import_loading = categories
        .iter()
        .find(|category| category["name"] == "package/import loading")
        .expect("package/import loading category should be present");
    assert!(
        package_import_loading["codes"]
            .as_array()
            .expect("package/import codes should be an array")
            .iter()
            .any(|code| code["code"] == "LNC0037" && code["title"] == "package metadata invalid")
    );
    let package_unsupported_feature_codes = package_import_loading["unsupported_feature_codes"]
        .as_array()
        .expect("package/import unsupported feature codes should be an array");
    assert!(
        package_unsupported_feature_codes
            .iter()
            .any(|code| code == "LNC0024")
    );

    let type_checking = categories
        .iter()
        .find(|category| category["name"] == "type checking")
        .expect("type checking category should be present");
    assert!(
        type_checking["codes"]
            .as_array()
            .expect("type checking codes should be an array")
            .iter()
            .any(|code| code["code"] == "LNC0027" && code["title"] == "call resolution failed")
    );
}

#[test]
fn cli_diagnostics_source_pack_progress_reports_artifact_record_counts_without_source_scan() {
    let root = common::temp_artifact_path(
        "laniusc_cli_diagnostics",
        "source_pack_progress_record",
        None,
    );
    let artifact_root = root.join("artifacts");
    let store = FilesystemArtifactStore::new(&artifact_root);
    let progress = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: SourcePackArtifactTarget::Wasm,
        work_item_count: 4,
        page_size: SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE,
        page_count: 1,
        artifact_item_count: 3,
        completed_item_count: 1,
        ready_item_count: 2,
        ready_artifact_item_count: 1,
        claimed_item_count: 1,
        first_ready_item_index: Some(2),
        first_ready_artifact_item_index: Some(2),
    };
    store
        .store_work_queue_progress_index(&progress)
        .expect("store source-pack work queue progress index");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("source-pack-progress")
        .arg("--source-pack-artifact-root")
        .arg(&artifact_root)
        .arg("--emit")
        .arg("wasm")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics source-pack-progress with trailing diagnostic format",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics source-pack-progress");

    assert!(
        output.status.success(),
        "source-pack progress diagnostics should accept trailing global diagnostic format\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "source-pack progress diagnostics should not print stderr\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("progress output should be JSON");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.source-pack-progress"
    );
    assert_eq!(
        document["artifact_root"],
        artifact_root.display().to_string()
    );
    assert_eq!(document["target"], "wasm");
    assert_eq!(
        document["data_source"],
        "source-pack work queue progress index artifact"
    );
    assert_eq!(
        document["record_contract"]["kind"],
        "source-pack-work-queue-progress-index"
    );
    assert_eq!(
        document["record_contract"]["schema_version"],
        SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION
    );
    assert_eq!(
        document["record_contract"]["expected_schema_version"],
        SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION
    );
    assert_eq!(
        document["record_contract"]["path"],
        store
            .work_queue_progress_index_path_for_target(SourcePackArtifactTarget::Wasm)
            .display()
            .to_string()
    );
    assert_eq!(document["status"], "ready");
    assert_eq!(document["progress"]["work_item_count"], 4);
    assert_eq!(document["progress"]["artifact_item_count"], 3);
    assert_eq!(document["progress"]["completed_item_count"], 1);
    assert_eq!(document["progress"]["ready_item_count"], 2);
    assert_eq!(document["progress"]["ready_artifact_item_count"], 1);
    assert_eq!(document["progress"]["claimed_item_count"], 1);
    assert_eq!(document["progress"]["first_ready_item_index"], 2);
    assert_eq!(document["progress"]["first_ready_artifact_item_index"], 2);
    assert_eq!(
        document["progress"]["page_size"],
        SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
    );
    assert_eq!(document["progress"]["page_count"], 1);
    assert_eq!(document["progress"]["complete"], false);
    assert_eq!(document["no_run_guards"], document["guards"]);
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert_eq!(document["guards"]["source_compilation"], false);
    assert_eq!(document["guards"]["source_scanning"], false);
    assert_eq!(document["guards"]["gpu_device_creation"], false);
    assert_eq!(document["guards"]["target_codegen"], false);
}

#[test]
fn cli_diagnostics_source_pack_progress_missing_artifact_record_can_render_json_diagnostic() {
    let root = common::temp_artifact_path(
        "laniusc_cli_diagnostics",
        "source_pack_progress_missing_record_json",
        None,
    );
    let artifact_root = root.join("artifacts");
    fs::create_dir_all(&artifact_root).expect("create empty artifact root");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("source-pack-progress")
        .arg("--source-pack-artifact-root")
        .arg(&artifact_root)
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics source-pack-progress JSON missing artifact record",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics source-pack-progress");
    fs::remove_dir_all(&root).expect("remove empty artifact root");

    assert!(
        !output.status.success(),
        "source-pack progress without a persisted progress record should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "source-pack progress artifact diagnostics should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(
        diagnostic["schema_version"],
        laniusc::compiler::DIAGNOSTIC_JSON_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["schema_name"],
        laniusc::compiler::DIAGNOSTIC_JSON_SCHEMA_NAME
    );
    assert_eq!(
        diagnostic["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0037");
    assert_eq!(diagnostic["category"], "package/import loading");
    assert!(diagnostic["primary_label"].is_null());
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0037"
    );
    assert!(
        diagnostic["help"]
            .as_str()
            .is_some_and(|help| help.contains("source-pack")),
        "diagnostic help should point users back to source-pack progress records\nstderr:\n{stderr}"
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("missing progress record diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("source-pack artifact root")),
        "diagnostic notes should identify the artifact root\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("source-pack progress index")),
        "diagnostic notes should identify the missing progress index\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_diagnostics_source_pack_progress_missing_artifact_record_can_render_lsp_json_diagnostic() {
    let root = common::temp_artifact_path(
        "laniusc_cli_diagnostics",
        "source_pack_progress_missing_record_lsp_json",
        None,
    );
    let artifact_root = root.join("artifacts");
    fs::create_dir_all(&artifact_root).expect("create empty artifact root");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("source-pack-progress")
        .arg("--source-pack-artifact-root")
        .arg(&artifact_root)
        .arg("--diagnostic-format=lsp-json");
    let output = command_output_with_timeout(
        "laniusc diagnostics source-pack-progress LSP JSON missing artifact record",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics source-pack-progress");
    fs::remove_dir_all(&root).expect("remove empty artifact root");

    assert!(
        !output.status.success(),
        "source-pack progress without a persisted progress record should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "source-pack progress artifact diagnostics should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "LSP JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one LSP diagnostic object");
    assert_eq!(diagnostic["severity"], 1);
    assert_eq!(diagnostic["code"], "LNC0037");
    assert_eq!(diagnostic["source"], "laniusc");
    assert_eq!(diagnostic["message"], "package metadata invalid");
    assert_eq!(
        diagnostic["data"]["schema_version"],
        laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["data"]["schema_name"],
        laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_NAME
    );
    assert_eq!(
        diagnostic["data"]["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(diagnostic["data"]["position_encoding"], "utf-16");
    assert_eq!(diagnostic["data"]["title"], "package metadata invalid");
    assert_eq!(diagnostic["data"]["category"], "package/import loading");
    assert_eq!(diagnostic["data"]["primary_label_policy"], "none");
    assert_eq!(
        diagnostic["data"]["explain_command"],
        "laniusc diagnostics explain LNC0037"
    );
    assert!(
        diagnostic["data"]["help"]
            .as_str()
            .is_some_and(|help| help.contains("source-pack")),
        "LSP diagnostic help should point users back to source-pack progress records\nstderr:\n{stderr}"
    );
    let notes = diagnostic["data"]["notes"]
        .as_array()
        .expect("LSP diagnostic data should carry missing-record notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("source-pack artifact root")),
        "LSP diagnostic notes should identify the artifact root\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("source-pack progress index")),
        "LSP diagnostic notes should identify the missing progress index\nstderr:\n{stderr}"
    );
    assert!(diagnostic["data"].get("primary_label").is_none());
    assert_eq!(diagnostic["range"]["start"]["line"], 0);
    assert_eq!(diagnostic["range"]["start"]["character"], 0);
    assert_eq!(diagnostic["range"]["end"]["line"], 0);
    assert_eq!(diagnostic["range"]["end"]["character"], 0);
    assert!(diagnostic.get("primary_label").is_none());
    assert!(diagnostic.get("notes").is_none());
    assert!(diagnostic.get("diagnostics").is_none());
}

#[test]
fn cli_diagnostics_source_pack_progress_missing_artifact_root_can_render_json_diagnostic() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("source-pack-progress")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics source-pack-progress JSON missing artifact root",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics source-pack-progress");

    assert!(
        !output.status.success(),
        "source-pack progress without an artifact root should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "source-pack progress option diagnostics should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(
        diagnostic["schema_version"],
        laniusc::compiler::DIAGNOSTIC_JSON_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0023");
    assert_eq!(diagnostic["category"], "tooling");
    assert!(diagnostic["primary_label"].is_null());
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0023"
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("missing artifact root diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--source-pack-artifact-root")),
        "diagnostic notes should identify the required option\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("source-pack artifact")),
        "diagnostic notes should describe the required artifact root\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_diagnostics_source_pack_progress_missing_artifact_root_can_render_lsp_json_diagnostic() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("source-pack-progress")
        .arg("--diagnostic-format=lsp-json");
    let output = command_output_with_timeout(
        "laniusc diagnostics source-pack-progress LSP JSON missing artifact root",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics source-pack-progress");

    assert!(
        !output.status.success(),
        "source-pack progress without an artifact root should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "source-pack progress option diagnostics should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "LSP JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one LSP diagnostic object");
    assert_eq!(diagnostic["severity"], 1);
    assert_eq!(diagnostic["code"], "LNC0023");
    assert_eq!(diagnostic["source"], "laniusc");
    assert_eq!(diagnostic["message"], "missing CLI option value");
    assert_eq!(
        diagnostic["data"]["schema_version"],
        laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["data"]["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(diagnostic["data"]["position_encoding"], "utf-16");
    assert_eq!(diagnostic["data"]["title"], "missing CLI option value");
    assert_eq!(diagnostic["data"]["category"], "tooling");
    assert_eq!(diagnostic["data"]["primary_label_policy"], "none");
    assert_eq!(
        diagnostic["data"]["explain_command"],
        "laniusc diagnostics explain LNC0023"
    );
    let notes = diagnostic["data"]["notes"]
        .as_array()
        .expect("LSP diagnostic data should carry missing-option notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--source-pack-artifact-root")),
        "LSP diagnostic notes should identify the required option\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("source-pack artifact")),
        "LSP diagnostic notes should describe the required artifact root\nstderr:\n{stderr}"
    );
    assert!(diagnostic["data"].get("primary_label").is_none());
    assert_eq!(diagnostic["range"]["start"]["line"], 0);
    assert_eq!(diagnostic["range"]["start"]["character"], 0);
    assert_eq!(diagnostic["range"]["end"]["line"], 0);
    assert_eq!(diagnostic["range"]["end"]["character"], 0);
    assert!(diagnostic.get("primary_label").is_none());
    assert!(diagnostic.get("notes").is_none());
    assert!(diagnostic.get("diagnostics").is_none());
}

#[test]
fn cli_diagnostics_formats_prints_machine_readable_contract_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command.arg("diagnostics").arg("formats");
    let output = command_output_with_timeout(
        "laniusc diagnostics formats",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics formats");

    assert!(
        output.status.success(),
        "diagnostics formats should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics formats should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let registry: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("formats output should be JSON");
    assert_eq!(
        registry["schema_version"],
        laniusc::compiler::DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_VERSION
    );
    assert_eq!(
        registry["schema_name"],
        laniusc::compiler::DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_NAME
    );
    assert_eq!(registry["cli_flag"], "--diagnostic-format");
    assert_eq!(registry["default_format"], "text");
    assert_eq!(
        registry["accepted_formats"]
            .as_array()
            .expect("accepted diagnostic formats should be an array")
            .iter()
            .map(|format| format
                .as_str()
                .expect("accepted diagnostic format should be a string"))
            .collect::<Vec<_>>(),
        vec!["text", "json", "lsp-json"],
        "formats command should expose the accepted selector values directly"
    );
    assert_eq!(registry["no_run_guards"]["source_compilation"], false);
    assert_eq!(registry["no_run_guards"]["source_scanning"], false);
    assert_eq!(registry["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(registry["no_run_guards"]["target_codegen"], false);

    let formats = registry["formats"]
        .as_array()
        .expect("diagnostic formats should be an array");
    assert!(formats.iter().any(|format| {
        format["name"] == "text"
            && format["output_stream"] == "stderr"
            && format["payload_schema_name"].is_null()
            && format["payload_schema_version"].is_null()
            && format["payload_schema_location"].is_null()
            && format["includes_source_snippet"] == true
            && format["formatter_check_supported"] == true
    }));
    assert!(formats.iter().any(|format| {
        format["name"] == "lsp-json"
            && format["payload"] == "LSP Diagnostic JSON object"
            && format["payload_schema_name"] == laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_NAME
            && format["payload_schema_version"]
                == laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
            && format["payload_schema_location"] == "data"
            && format["position_encoding"] == "utf-16"
            && format["language_server_envelope"] == false
            && format["formatter_check_supported"] == true
            && format["description"]
                .as_str()
                .is_some_and(|description| !description.trim().is_empty())
    }));
}

#[test]
fn cli_diagnostics_formatter_prints_no_run_formatter_policy() {
    let mut command = Command::new(laniusc_bin());
    command.arg("diagnostics").arg("formatter");
    let output = command_output_with_timeout(
        "laniusc diagnostics formatter",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics formatter");

    assert!(
        output.status.success(),
        "diagnostics formatter should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics formatter should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let policy: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("formatter policy output should be JSON");
    assert_eq!(policy["schema_name"], "laniusc.formatter.policy");
    assert_eq!(policy["schema_version"], 1);
    assert_eq!(
        policy["formatter_contract"],
        "unstable-alpha lexical full-document formatter"
    );
    assert_eq!(policy["stability"], "unstable-alpha");
    assert_eq!(policy["formatter_kind"], "lexical");
    assert_eq!(policy["document_scope"], "full-document");
    assert_eq!(policy["range_formatting"], false);
    assert_eq!(policy["syntax_parsing"], false);
    assert_eq!(policy["type_checking"], false);
    assert_eq!(policy["import_resolution"], false);
    assert_eq!(policy["semantic_rewrites"], false);
    assert!(
        policy["token_preservation"]
            .as_str()
            .is_some_and(|contract| contract.contains("non-whitespace token text")
                && contract.contains("token order")),
        "formatter policy should describe token-preservation behavior\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert_eq!(policy["line_endings"], "lf");
    assert_eq!(policy["indent"]["style"], "spaces");
    assert_eq!(policy["indent"]["size"], 4);
    assert_eq!(policy["cli"]["format_stdin"], "laniusc fmt --stdin");
    assert_eq!(policy["cli"]["check_stdin"], "laniusc fmt --stdin --check");
    assert_eq!(policy["cli"]["format_files"], "laniusc fmt <input.lani>...");
    assert_eq!(
        policy["cli"]["check_files"],
        "laniusc fmt --check <input.lani>..."
    );
    assert_eq!(policy["lsp"]["method"], "textDocument/formatting");
    assert_eq!(
        policy["lsp"]["edit_strategy"],
        "single full-document replacement when formatting changes"
    );
    assert_eq!(
        policy["lsp"]["request_options"]["params_options_required"],
        true
    );
    assert_eq!(policy["lsp"]["request_options"]["tab_size"], 4);
    assert_eq!(policy["lsp"]["request_options"]["insert_spaces"], true);
    assert_eq!(policy["diagnostic_codes"]["check_failed"], "LNC0019");
    assert_eq!(policy["diagnostic_codes"]["input_read_failed"], "LNC0040");
    assert_eq!(policy["diagnostic_codes"]["output_write_failed"], "LNC0034");
    assert_eq!(
        policy["diagnostic_codes"]["output_stream_failed"],
        "LNC0035"
    );
    assert_eq!(policy["no_run_guards"]["source_compilation"], false);
    assert_eq!(policy["no_run_guards"]["source_scanning"], false);
    assert_eq!(policy["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(policy["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(policy["no_run_guards"]["target_codegen"], false);
    assert_eq!(policy["no_run_guards"]["slangc_probe"], false);
    assert_eq!(policy["no_run_guards"]["pareas_invocation"], false);
}

#[test]
fn cli_diagnostics_version_policy_prints_no_run_tooling_contract() {
    let mut command = Command::new(laniusc_bin());
    command.arg("diagnostics").arg("version-policy");
    let output = command_output_with_timeout(
        "laniusc diagnostics version-policy",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics version-policy");

    assert!(
        output.status.success(),
        "diagnostics version-policy should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics version-policy should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let policy: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("version policy output should be JSON");
    assert_eq!(policy["schema_version"], 6);
    assert_eq!(policy["schema_name"], "laniusc.diagnostics.version-policy");
    assert_eq!(policy["compiler"]["name"], "laniusc");
    assert_eq!(
        policy["compiler"]["package_version"],
        env!("CARGO_PKG_VERSION")
    );
    assert_eq!(policy["compiler"]["language_edition"], "unstable-alpha");
    assert!(
        policy["compiler"]["edition_policy"]
            .as_str()
            .is_some_and(|policy| policy.contains("no stable production language edition yet"))
    );
    assert_eq!(policy["distribution"]["release_channel"], "source-worktree");
    assert_eq!(policy["distribution"]["production_release_claim"], false);
    assert_eq!(policy["distribution"]["stable_install_artifact"], false);
    assert_eq!(policy["distribution"]["package_manager_channel"], false);
    assert_eq!(
        policy["distribution"]["source_control_required_for_claims"],
        true
    );
    assert!(
        policy["compatibility"]["machine_readable_contract"]
            .as_str()
            .is_some_and(|contract| {
                contract.contains("schema_name") && contract.contains("schema_version")
            })
    );
    assert_eq!(policy["target_surface"]["emit_targets"], "x86_64, wasm");
    assert_eq!(policy["target_surface"]["default_emit_target"], "x86_64");
    assert_eq!(
        policy["target_surface"]["target_triples"],
        "x86_64-unknown-linux-gnu, wasm32-unknown-unknown"
    );
    assert_eq!(
        policy["tooling"]["diagnostic_registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(
        policy["tooling"]["diagnostic_output_formats_schema_version"],
        laniusc::compiler::DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_VERSION
    );
    assert_eq!(
        policy["tooling"]["formatter"],
        "unstable-alpha lexical full-document formatter"
    );
    assert_eq!(
        policy["tooling"]["formatter_policy"]["schema_name"],
        "laniusc.formatter.policy"
    );
    assert_eq!(policy["tooling"]["formatter_policy"]["schema_version"], 1);
    assert_eq!(
        policy["tooling"]["formatter_policy"]["token_preservation"],
        "preserves non-whitespace token text and token order; rewrites whitespace, newlines, and indentation only"
    );
    assert_eq!(
        policy["tooling"]["formatter_policy"]["no_run_guards"]["source_scanning"],
        false
    );
    assert_eq!(
        policy["tooling"]["lsp_error_data_schema_name"],
        "laniusc.lsp.error-data"
    );
    let command_discovery = &policy["tooling"]["command_discovery"];
    assert_eq!(command_discovery["schema_version"], 3);
    assert_eq!(
        command_discovery["schema_name"],
        "laniusc.diagnostics.command-discovery"
    );
    assert!(
        command_discovery["policy"]
            .as_str()
            .is_some_and(|policy| policy.contains("machine-readable")
                && policy.contains("instead of scraping --help")),
        "version-policy should tell wrappers how to discover tooling metadata\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert_eq!(
        command_discovery["preferred_policy_command"],
        "laniusc diagnostics version-policy"
    );
    assert_eq!(command_discovery["human_help_command"], "laniusc --help");
    assert!(
        command_discovery["placeholder_policy"]
            .as_str()
            .is_some_and(|policy| {
                policy.contains("uppercase words") && policy.contains("user-supplied arguments")
            }),
        "version-policy should explain command-template placeholders for wrappers\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert_eq!(
        command_discovery["no_run_guards"]["source_compilation"],
        false
    );
    assert_eq!(command_discovery["no_run_guards"]["source_scanning"], false);
    assert_eq!(
        command_discovery["no_run_guards"]["gpu_device_creation"],
        false
    );
    assert_eq!(command_discovery["no_run_guards"]["target_codegen"], false);
    let discovery_commands = command_discovery["commands"]
        .as_array()
        .expect("version-policy should list no-run discovery commands");
    let command_names = discovery_commands
        .iter()
        .map(|command| {
            command["command"]
                .as_str()
                .expect("discovery command rows should publish copyable commands")
                .to_string()
        })
        .collect::<std::collections::BTreeSet<_>>();
    let placeholders = command_discovery["placeholders"]
        .as_array()
        .expect("version-policy should describe command-template placeholders");
    assert_eq!(
        command_discovery["placeholder_count"].as_u64(),
        Some(placeholders.len() as u64)
    );
    let mut placeholder_rows = std::collections::BTreeMap::new();
    for placeholder in placeholders {
        let name = placeholder["placeholder"]
            .as_str()
            .expect("placeholder rows should publish a placeholder name");
        assert!(
            placeholder_rows
                .insert(name.to_string(), placeholder)
                .is_none(),
            "placeholder {name} should appear once"
        );
        assert!(
            placeholder["meaning"]
                .as_str()
                .is_some_and(|meaning| !meaning.trim().is_empty()),
            "placeholder {name} should describe the user-supplied argument"
        );
        assert!(
            placeholder["bulk_discovery_command"]
                .as_str()
                .is_some_and(|command| command_names.contains(command)),
            "placeholder {name} should point at a listed discovery command"
        );
        assert!(
            placeholder["accepted_selector_examples"]
                .as_array()
                .is_some_and(|examples| !examples.is_empty()
                    && examples.iter().all(|example| example
                        .as_str()
                        .is_some_and(|example| !example.is_empty()))),
            "placeholder {name} should include selector examples"
        );
        let used_by = placeholder["used_by"]
            .as_array()
            .expect("placeholder rows should list command templates that use them");
        assert!(
            !used_by.is_empty(),
            "placeholder {name} should name at least one command template"
        );
        for command in used_by {
            let command = command
                .as_str()
                .expect("placeholder used_by entries should be command strings");
            assert!(
                command_names.contains(command),
                "placeholder {name} should only reference listed commands"
            );
        }
    }
    for expected_placeholder in ["CODE", "API", "SERVICE", "DIR"] {
        assert!(
            placeholder_rows.contains_key(expected_placeholder),
            "version-policy should define placeholder {expected_placeholder}"
        );
    }
    let selector_policies = command_discovery["selector_result_policies"]
        .as_array()
        .expect("version-policy should describe focused selector result policies");
    assert_eq!(
        command_discovery["selector_policy_count"].as_u64(),
        Some(selector_policies.len() as u64)
    );
    let mut selector_policy_rows = std::collections::BTreeMap::new();
    for selector_policy in selector_policies {
        let placeholder = selector_policy["placeholder"]
            .as_str()
            .expect("selector policy should name its placeholder");
        assert!(
            placeholder_rows.contains_key(placeholder),
            "selector policy placeholder {placeholder} should have a placeholder metadata row"
        );
        assert!(
            selector_policy_rows
                .insert(placeholder.to_string(), selector_policy)
                .is_none(),
            "selector policy placeholder {placeholder} should appear once"
        );
        let policy_commands = selector_policy["commands"]
            .as_array()
            .expect("selector policy should list covered command templates");
        assert!(
            !policy_commands.is_empty(),
            "selector policy {placeholder} should name at least one command"
        );
        for command in policy_commands {
            let command = command
                .as_str()
                .expect("selector policy command should be a string");
            assert!(
                command_names.contains(command),
                "selector policy {placeholder} should only reference listed commands"
            );
        }
        assert!(
            selector_policy["missing_selector_diagnostic_code"]
                .as_str()
                .is_some_and(|code| code.starts_with("LNC")),
            "selector policy {placeholder} should publish the missing-selector diagnostic code"
        );
        assert!(
            selector_policy["unknown_selector_behavior"]
                .as_str()
                .is_some_and(|behavior| !behavior.trim().is_empty()),
            "selector policy {placeholder} should explain unknown-selector behavior"
        );
    }
    for expected_placeholder in ["CODE", "API", "SERVICE", "DIR"] {
        assert!(
            selector_policy_rows.contains_key(expected_placeholder),
            "version-policy should define selector result policy {expected_placeholder}"
        );
    }
    assert_eq!(
        json_string_array(
            selector_policy_rows
                .get("CODE")
                .expect("CODE selector policy should be present"),
            "commands"
        ),
        vec![
            "laniusc diagnostics code CODE",
            "laniusc diagnostics explain CODE"
        ]
    );
    assert_eq!(
        selector_policy_rows
            .get("CODE")
            .expect("CODE selector policy should be present")["known_field"],
        "known"
    );
    assert!(
        selector_policy_rows
            .get("SERVICE")
            .expect("SERVICE selector policy should be present")["unknown_selector_behavior"]
            .as_str()
            .is_some_and(|behavior| behavior.contains("known: false"))
    );
    assert_eq!(
        selector_policy_rows
            .get("DIR")
            .expect("DIR selector policy should be present")["missing_selector_diagnostic_code"],
        "LNC0023"
    );
    assert!(
        selector_policy_rows
            .get("DIR")
            .expect("DIR selector policy should be present")["known_field"]
            .is_null()
    );
    let mut referenced_placeholders = std::collections::BTreeSet::new();
    for command_name in &command_names {
        for token in command_name.split_whitespace().filter(|token| {
            token
                .chars()
                .all(|character| character.is_ascii_uppercase())
        }) {
            referenced_placeholders.insert(token.to_string());
            assert!(
                placeholder_rows.contains_key(token),
                "command template placeholder {token} should have a metadata row"
            );
        }
    }
    for placeholder in placeholder_rows.keys() {
        assert!(
            referenced_placeholders.contains(placeholder),
            "placeholder {placeholder} should be used by at least one command template"
        );
    }
    assert_eq!(
        command_discovery["command_count"].as_u64(),
        Some(discovery_commands.len() as u64)
    );
    for command in discovery_commands {
        assert!(
            command["command"]
                .as_str()
                .is_some_and(|command| !command.trim().is_empty()),
            "discovery command rows should publish copyable commands\nstdout:\n{}",
            String::from_utf8_lossy(&output.stdout)
        );
        assert!(
            command["schema_name"]
                .as_str()
                .is_some_and(|schema| schema.starts_with("laniusc.")),
            "discovery command rows should publish payload schema names\nstdout:\n{}",
            String::from_utf8_lossy(&output.stdout)
        );
        assert!(
            command["purpose"]
                .as_str()
                .is_some_and(|purpose| !purpose.trim().is_empty()),
            "discovery command rows should describe their public purpose\nstdout:\n{}",
            String::from_utf8_lossy(&output.stdout)
        );
        assert_eq!(
            command["source_input"],
            false,
            "discovery command rows should classify source inputs explicitly\nstdout:\n{}",
            String::from_utf8_lossy(&output.stdout)
        );
        assert!(
            matches!(
                command["input_kind"].as_str(),
                Some("none")
                    | Some("selector")
                    | Some("source-pack-artifact-root")
                    | Some("toolchain-metadata")
            ),
            "discovery command rows should publish a stable input kind\nstdout:\n{}",
            String::from_utf8_lossy(&output.stdout)
        );
        assert!(
            command["artifact_input"].is_boolean(),
            "discovery command rows should classify artifact inputs explicitly\nstdout:\n{}",
            String::from_utf8_lossy(&output.stdout)
        );
        assert!(
            command["no_run_boundary"]
                .as_str()
                .is_some_and(|boundary| boundary.contains("metadata query")
                    && boundary.contains("source compilation")),
            "discovery command rows should describe their no-run boundary\nstdout:\n{}",
            String::from_utf8_lossy(&output.stdout)
        );
    }
    let find_discovery_command = |command_name: &str| {
        discovery_commands.iter().find(|command| {
            command["command"]
                .as_str()
                .is_some_and(|command| command == command_name)
        })
    };
    assert_eq!(
        find_discovery_command("laniusc diagnostics codes")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.diagnostics.codes")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics code CODE")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.diagnostics.code")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics code CODE")
            .and_then(|command| command["selector_placeholder"].as_str()),
        Some("CODE")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics categories")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.diagnostics.categories")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics formats")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.diagnostics.output-formats")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics formatter")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.formatter.policy")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics explain CODE")
            .and_then(|command| command["schema_name"].as_str()),
        Some(laniusc::compiler::DIAGNOSTIC_EXPLANATION_SCHEMA_NAME)
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics runtime-api API")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.diagnostics.runtime-api")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics runtime-api API")
            .and_then(|command| command["selector_placeholder"].as_str()),
        Some("API")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics runtime-apis")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.diagnostics.runtime-apis")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics runtime-service SERVICE")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.diagnostics.runtime-service")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics runtime-service SERVICE")
            .and_then(|command| command["selector_placeholder"].as_str()),
        Some("SERVICE")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics runtime-service-apis SERVICE")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.diagnostics.runtime-service-apis")
    );
    assert_eq!(
        find_discovery_command("laniusc diagnostics runtime-services")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.diagnostics.runtime-services")
    );
    assert_eq!(
        find_discovery_command(
            "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR"
        )
        .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.diagnostics.source-pack-progress")
    );
    assert_eq!(
        find_discovery_command(
            "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR"
        )
        .and_then(|command| command["input_kind"].as_str()),
        Some("source-pack-artifact-root")
    );
    assert_eq!(
        find_discovery_command(
            "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR"
        )
        .and_then(|command| command["artifact_input"].as_bool()),
        Some(true)
    );
    assert_eq!(
        find_discovery_command("laniusc lsp capabilities")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.lsp.capabilities")
    );
    assert_eq!(
        find_discovery_command("laniusc doctor --skip-slangc-probe")
            .and_then(|command| command["schema_name"].as_str()),
        Some("laniusc.doctor.report")
    );
    assert_eq!(
        find_discovery_command("laniusc doctor --skip-slangc-probe")
            .and_then(|command| command["input_kind"].as_str()),
        Some("toolchain-metadata")
    );
    assert_eq!(policy["no_run_guards"]["source_compilation"], false);
    assert_eq!(policy["no_run_guards"]["source_scanning"], false);
    assert_eq!(policy["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(policy["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(policy["no_run_guards"]["target_codegen"], false);
    assert_eq!(policy["no_run_guards"]["slangc_probe"], false);
    assert_eq!(
        policy["no_run_guards"]["shader_loop_audit_execution"],
        false
    );
    assert_eq!(policy["no_run_guards"]["pareas_invocation"], false);
}

#[test]
fn cli_diagnostics_commands_prints_no_run_command_discovery_index() {
    let mut command = Command::new(laniusc_bin());
    command.arg("diagnostics").arg("commands");
    let output = command_output_with_timeout(
        "laniusc diagnostics commands",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics commands");

    assert!(
        output.status.success(),
        "diagnostics commands should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics commands should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("command discovery output should be JSON");
    assert_eq!(document["schema_version"], 3);
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.command-discovery"
    );
    assert_eq!(
        document["command_index_command"],
        "laniusc diagnostics commands"
    );
    assert_eq!(
        document["preferred_policy_command"],
        "laniusc diagnostics version-policy"
    );
    assert_eq!(document["human_help_command"], "laniusc --help");
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert_eq!(document["no_run_guards"]["slangc_probe"], false);
    assert_eq!(
        document["no_run_guards"]["shader_loop_audit_execution"],
        false
    );
    assert_eq!(document["no_run_guards"]["pareas_invocation"], false);

    let commands = document["commands"]
        .as_array()
        .expect("command discovery should include command rows");
    assert_eq!(
        document["command_count"].as_u64(),
        Some(commands.len() as u64)
    );
    let command_rows = commands
        .iter()
        .map(|row| {
            let command = row["command"]
                .as_str()
                .expect("command row should expose a copyable command")
                .to_string();
            (command, row)
        })
        .collect::<std::collections::BTreeMap<_, _>>();
    assert_eq!(
        command_rows
            .get("laniusc diagnostics commands")
            .and_then(|row| row["schema_name"].as_str()),
        Some("laniusc.diagnostics.command-discovery")
    );
    assert_eq!(
        command_rows
            .get("laniusc diagnostics version-policy")
            .and_then(|row| row["schema_name"].as_str()),
        Some("laniusc.diagnostics.version-policy")
    );
    assert_eq!(
        command_rows
            .get("laniusc diagnostics formatter")
            .and_then(|row| row["schema_name"].as_str()),
        Some("laniusc.formatter.policy")
    );
    assert_eq!(
        command_rows
            .get("laniusc diagnostics runtime-service-apis SERVICE")
            .and_then(|row| row["schema_name"].as_str()),
        Some("laniusc.diagnostics.runtime-service-apis")
    );
    assert_eq!(
        command_rows
            .get("laniusc diagnostics runtime-service-apis SERVICE")
            .and_then(|row| row["selector_placeholder"].as_str()),
        Some("SERVICE")
    );
    assert_eq!(
        command_rows
            .get("laniusc lsp capabilities")
            .and_then(|row| row["schema_name"].as_str()),
        Some("laniusc.lsp.capabilities")
    );
    assert!(commands.iter().all(|row| {
        row["purpose"]
            .as_str()
            .is_some_and(|purpose| !purpose.trim().is_empty())
    }));
    assert!(commands.iter().all(|row| row["source_input"] == false));
    assert!(
        commands
            .iter()
            .all(|row| row["artifact_input"].is_boolean())
    );
    assert!(commands.iter().all(|row| {
        row["no_run_boundary"]
            .as_str()
            .is_some_and(|boundary| boundary.contains("metadata query"))
    }));
    assert!(
        command_rows.get("laniusc diagnostics codes").is_some_and(
            |row| row["selector_placeholder"].is_null()
                && row["input_kind"] == "none"
                && row["artifact_input"] == false
        )
    );
    assert!(
        command_rows
            .get("laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR")
            .is_some_and(|row| row["selector_placeholder"] == "DIR"
                && row["input_kind"] == "source-pack-artifact-root"
                && row["artifact_input"] == true
                && row["source_input"] == false)
    );

    let placeholders = document["placeholders"]
        .as_array()
        .expect("command discovery should include placeholder metadata");
    assert_eq!(
        document["placeholder_count"].as_u64(),
        Some(placeholders.len() as u64)
    );
    let placeholder_rows = placeholders
        .iter()
        .map(|row| {
            let placeholder = row["placeholder"]
                .as_str()
                .expect("placeholder row should expose a placeholder")
                .to_string();
            (placeholder, row)
        })
        .collect::<std::collections::BTreeMap<_, _>>();
    assert_eq!(
        placeholder_rows
            .get("CODE")
            .and_then(|row| row["bulk_discovery_command"].as_str()),
        Some("laniusc diagnostics codes")
    );
    assert_eq!(
        placeholder_rows
            .get("API")
            .and_then(|row| row["bulk_discovery_command"].as_str()),
        Some("laniusc diagnostics runtime-apis")
    );
    assert_eq!(
        placeholder_rows
            .get("SERVICE")
            .and_then(|row| row["bulk_discovery_command"].as_str()),
        Some("laniusc diagnostics runtime-services")
    );
    assert_eq!(
        placeholder_rows
            .get("DIR")
            .and_then(|row| row["bulk_discovery_command"].as_str()),
        Some("laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR")
    );

    let selector_policies = document["selector_result_policies"]
        .as_array()
        .expect("command discovery should include selector result policies");
    assert_eq!(
        document["selector_policy_count"].as_u64(),
        Some(selector_policies.len() as u64)
    );
    let selector_policy_rows = selector_policies
        .iter()
        .map(|row| {
            let placeholder = row["placeholder"]
                .as_str()
                .expect("selector policy should expose a placeholder")
                .to_string();
            (placeholder, row)
        })
        .collect::<std::collections::BTreeMap<_, _>>();
    assert_eq!(
        selector_policy_rows.len(),
        selector_policies.len(),
        "selector result policies should not duplicate placeholders"
    );

    let code_policy = selector_policy_rows
        .get("CODE")
        .expect("command discovery should describe CODE selector behavior");
    assert_eq!(
        json_string_array(code_policy, "commands"),
        vec![
            "laniusc diagnostics code CODE",
            "laniusc diagnostics explain CODE"
        ]
    );
    assert_eq!(code_policy["missing_selector_diagnostic_code"], "LNC0026");
    assert!(
        code_policy["unknown_selector_behavior"]
            .as_str()
            .is_some_and(|behavior| behavior.contains("known: false"))
    );
    assert_eq!(code_policy["known_field"], "known");

    let api_policy = selector_policy_rows
        .get("API")
        .expect("command discovery should describe API selector behavior");
    assert_eq!(
        json_string_array(api_policy, "commands"),
        vec!["laniusc diagnostics runtime-api API"]
    );
    assert_eq!(api_policy["missing_selector_diagnostic_code"], "LNC0026");
    assert_eq!(api_policy["known_field"], "known");

    let service_policy = selector_policy_rows
        .get("SERVICE")
        .expect("command discovery should describe SERVICE selector behavior");
    assert_eq!(
        json_string_array(service_policy, "commands"),
        vec![
            "laniusc diagnostics runtime-service SERVICE",
            "laniusc diagnostics runtime-service-apis SERVICE"
        ]
    );
    assert_eq!(
        service_policy["missing_selector_diagnostic_code"],
        "LNC0026"
    );
    assert!(
        service_policy["unknown_selector_behavior"]
            .as_str()
            .is_some_and(|behavior| behavior.contains("known: false"))
    );
    assert_eq!(service_policy["known_field"], "known");

    let dir_policy = selector_policy_rows
        .get("DIR")
        .expect("command discovery should describe DIR selector behavior");
    assert_eq!(
        json_string_array(dir_policy, "commands"),
        vec!["laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR"]
    );
    assert_eq!(dir_policy["missing_selector_diagnostic_code"], "LNC0023");
    assert!(
        dir_policy["unknown_selector_behavior"]
            .as_str()
            .is_some_and(
                |behavior| behavior.contains("LNC0037") && behavior.contains("artifact record")
            )
    );
    assert!(dir_policy["known_field"].is_null());
}

#[test]
fn cli_diagnostics_version_policy_embeds_command_discovery_index_without_source_scan() {
    let mut commands_command = Command::new(laniusc_bin());
    commands_command.arg("diagnostics").arg("commands");
    let commands_output = command_output_with_timeout(
        "laniusc diagnostics commands projection source",
        &mut commands_command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics commands");
    assert!(
        commands_output.status.success(),
        "diagnostics commands should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&commands_output.stdout),
        String::from_utf8_lossy(&commands_output.stderr)
    );
    assert!(
        commands_output.stderr.is_empty(),
        "diagnostics commands should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&commands_output.stderr)
    );

    let mut version_command = Command::new(laniusc_bin());
    version_command.arg("diagnostics").arg("version-policy");
    let version_output = command_output_with_timeout(
        "laniusc diagnostics version-policy command discovery projection",
        &mut version_command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics version-policy");
    assert!(
        version_output.status.success(),
        "diagnostics version-policy should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&version_output.stdout),
        String::from_utf8_lossy(&version_output.stderr)
    );
    assert!(
        version_output.stderr.is_empty(),
        "diagnostics version-policy should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&version_output.stderr)
    );

    let commands_document: serde_json::Value = serde_json::from_slice(&commands_output.stdout)
        .expect("command discovery output should be JSON");
    let version_policy: serde_json::Value = serde_json::from_slice(&version_output.stdout)
        .expect("version-policy output should be JSON");
    let embedded_discovery = &version_policy["tooling"]["command_discovery"];
    assert_eq!(
        embedded_discovery,
        &commands_document,
        "version-policy should embed the same command-discovery contract printed by the focused CLI command\ncommands stdout:\n{}\nversion-policy stdout:\n{}",
        String::from_utf8_lossy(&commands_output.stdout),
        String::from_utf8_lossy(&version_output.stdout)
    );
    assert_eq!(
        commands_document["no_run_guards"]["source_compilation"],
        false
    );
    assert_eq!(commands_document["no_run_guards"]["source_scanning"], false);
    assert_eq!(
        commands_document["no_run_guards"]["stdlib_source_scanning"],
        false
    );
    assert_eq!(
        commands_document["no_run_guards"]["gpu_device_creation"],
        false
    );
    assert_eq!(commands_document["no_run_guards"]["target_codegen"], false);
    assert_eq!(commands_document["no_run_guards"]["slangc_probe"], false);
    assert_eq!(
        commands_document["no_run_guards"]["shader_loop_audit_execution"],
        false
    );
    assert_eq!(
        commands_document["no_run_guards"]["pareas_invocation"],
        false
    );
    assert_eq!(version_policy["no_run_guards"]["source_compilation"], false);
    assert_eq!(version_policy["no_run_guards"]["source_scanning"], false);
    assert_eq!(
        version_policy["no_run_guards"]["stdlib_source_scanning"],
        false
    );
    assert_eq!(
        version_policy["no_run_guards"]["gpu_device_creation"],
        false
    );
    assert_eq!(version_policy["no_run_guards"]["target_codegen"], false);
    assert_eq!(version_policy["no_run_guards"]["slangc_probe"], false);
    assert_eq!(
        version_policy["no_run_guards"]["shader_loop_audit_execution"],
        false
    );
    assert_eq!(version_policy["no_run_guards"]["pareas_invocation"], false);

    let command_rows = commands_document["commands"]
        .as_array()
        .expect("command discovery should include command rows");
    for expected_command in [
        "laniusc diagnostics registry",
        "laniusc diagnostics codes",
        "laniusc diagnostics explain CODE",
        "laniusc diagnostics runtime-apis",
        "laniusc diagnostics runtime-services",
        "laniusc diagnostics source-pack-progress --source-pack-artifact-root DIR",
        "laniusc lsp capabilities",
        "laniusc doctor --skip-slangc-probe",
    ] {
        assert!(
            command_rows
                .iter()
                .any(|row| row["command"] == expected_command),
            "command discovery should list {expected_command} without relying on help text\nstdout:\n{}",
            String::from_utf8_lossy(&commands_output.stdout)
        );
    }
}

#[test]
fn cli_global_diagnostic_format_before_no_run_subcommand_keeps_query_routing() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=json")
        .arg("diagnostics")
        .arg("formats");
    let output = command_output_with_timeout(
        "laniusc --diagnostic-format=json diagnostics formats",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics formats with leading diagnostic format");

    assert!(
        output.status.success(),
        "leading diagnostic-format selector should not turn diagnostics into an input path\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "successful no-run diagnostics query should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let registry: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("formats output should be JSON");
    assert_eq!(
        registry["schema_version"],
        laniusc::compiler::DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_VERSION
    );
    assert_eq!(
        registry["schema_name"],
        laniusc::compiler::DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_NAME
    );
    assert_eq!(registry["cli_flag"], "--diagnostic-format");
    assert_eq!(registry["default_format"], "text");
    assert_eq!(
        registry["accepted_formats"]
            .as_array()
            .expect("accepted diagnostic formats should be an array")
            .iter()
            .map(|format| format
                .as_str()
                .expect("accepted diagnostic format should be a string"))
            .collect::<Vec<_>>(),
        vec!["text", "json", "lsp-json"]
    );
    assert_eq!(registry["no_run_guards"]["source_compilation"], false);
    assert_eq!(registry["no_run_guards"]["source_scanning"], false);
    assert_eq!(registry["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(registry["no_run_guards"]["target_codegen"], false);
}

#[test]
fn cli_diagnostics_explain_prints_single_code_json_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command.arg("diagnostics").arg("explain").arg("lnc0017");
    let output = command_output_with_timeout(
        "laniusc diagnostics explain LNC0017",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics explain");

    assert!(
        output.status.success(),
        "diagnostics explain should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics explain should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let explanation: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("explain output should be JSON");
    assert_eq!(
        explanation["schema_version"],
        laniusc::compiler::DIAGNOSTIC_EXPLANATION_SCHEMA_VERSION
    );
    assert_eq!(
        explanation["schema_name"],
        laniusc::compiler::DIAGNOSTIC_EXPLANATION_SCHEMA_NAME
    );
    assert_eq!(
        explanation["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(explanation["requested_code"], "LNC0017");
    assert_eq!(
        explanation["explain_command"],
        "laniusc diagnostics explain LNC0017"
    );
    assert_eq!(explanation["known"], true);
    assert_eq!(explanation["diagnostic"]["code"], "LNC0017");
    assert_eq!(explanation["diagnostic"]["title"], "x86 backend boundary");
    assert_eq!(explanation["diagnostic"]["category"], "native codegen");
    assert_eq!(
        explanation["diagnostic"]["primary_label_policy"],
        "required"
    );
    assert_eq!(explanation["diagnostic"]["default_severity"], "error");
    assert_eq!(explanation["diagnostic"]["lsp_source"], "laniusc");
    assert_eq!(explanation["diagnostic"]["lsp_severity"], 1);
    assert_eq!(explanation["unsupported_feature"]["code"], "LNC0017");
    assert_eq!(
        explanation["unsupported_feature"]["boundary"],
        "x86 backend"
    );
    assert!(
        explanation["unsupported_feature"]["summary"]
            .as_str()
            .expect("unsupported summary should be a string")
            .contains("native-codegen")
    );
    assert!(
        explanation["unsupported_feature"]["next_step"]
            .as_str()
            .expect("unsupported next_step should be a string")
            .contains("--emit=wasm")
    );
    assert_eq!(
        explanation["codegen_boundary"]["diagnostic_code"],
        "LNC0017"
    );
    assert_eq!(explanation["codegen_boundary"]["boundary"], "x86 backend");
    assert_eq!(explanation["codegen_boundary"]["target"], "x86_64");
    assert_eq!(
        explanation["codegen_boundary"]["stage"],
        "native codegen lowering"
    );
    assert_eq!(
        explanation["codegen_boundary"]["partial_artifact_policy"],
        "fail-closed before emitting a partial instruction prefix"
    );
    assert_eq!(
        explanation["codegen_boundary"]["target_bytes_emitted"],
        false
    );
    assert_eq!(
        explanation["codegen_boundary"]["diagnostics_only_command"],
        "laniusc check"
    );
    assert_eq!(explanation["codegen_boundary"]["fallback_emit"], "wasm");
    assert!(explanation["runtime_service_boundaries"].is_null());
    assert!(explanation["runtime_bound_apis"].is_null());
}

#[test]
fn cli_diagnostics_explain_accepts_copied_error_code_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("explain")
        .arg("error[lnc0038]: runtime service boundary");
    let output = command_output_with_timeout(
        "laniusc diagnostics explain copied LNC0038 diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics explain");

    assert!(
        output.status.success(),
        "diagnostics explain should accept a copied rendered diagnostic code\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics explain should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let explanation: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("explain output should be JSON");
    assert_eq!(explanation["requested_code"], "LNC0038");
    assert_eq!(explanation["known"], true);
    assert_eq!(explanation["diagnostic"]["code"], "LNC0038");
    assert_eq!(explanation["diagnostic"]["category"], "runtime binding");
    assert_eq!(
        explanation["unsupported_feature"]["boundary"],
        "runtime service binding"
    );
    assert!(
        explanation["runtime_service_boundaries"]
            .as_array()
            .is_some_and(|services| !services.is_empty()),
        "copied diagnostic explanation should still include runtime service rows"
    );
}

#[test]
fn cli_diagnostics_explain_describes_wasm_codegen_boundary_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command.arg("diagnostics").arg("explain").arg("lnc0036");
    let output = command_output_with_timeout(
        "laniusc diagnostics explain LNC0036",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics explain");

    assert!(
        output.status.success(),
        "diagnostics explain should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics explain should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let explanation: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("explain output should be JSON");
    assert_eq!(explanation["requested_code"], "LNC0036");
    assert_eq!(explanation["known"], true);
    assert_eq!(explanation["diagnostic"]["code"], "LNC0036");
    assert_eq!(explanation["diagnostic"]["title"], "WASM backend boundary");
    assert_eq!(explanation["diagnostic"]["category"], "target codegen");
    assert_eq!(explanation["unsupported_feature"]["code"], "LNC0036");
    assert_eq!(
        explanation["unsupported_feature"]["boundary"],
        "WASM backend"
    );
    assert!(
        explanation["unsupported_feature"]["summary"]
            .as_str()
            .expect("unsupported summary should be a string")
            .contains("WASM-codegen")
    );
    assert!(
        explanation["unsupported_feature"]["next_step"]
            .as_str()
            .expect("unsupported next_step should be a string")
            .contains("laniusc check")
    );
    assert_eq!(
        explanation["codegen_boundary"]["diagnostic_code"],
        "LNC0036"
    );
    assert_eq!(explanation["codegen_boundary"]["boundary"], "WASM backend");
    assert_eq!(explanation["codegen_boundary"]["target"], "wasm");
    assert_eq!(
        explanation["codegen_boundary"]["stage"],
        "WASM codegen lowering"
    );
    assert_eq!(
        explanation["codegen_boundary"]["partial_artifact_policy"],
        "fail-closed before emitting a partial module prefix"
    );
    assert_eq!(
        explanation["codegen_boundary"]["target_bytes_emitted"],
        false
    );
    assert_eq!(
        explanation["codegen_boundary"]["diagnostics_only_command"],
        "laniusc check"
    );
    assert!(explanation["codegen_boundary"]["fallback_emit"].is_null());
    assert_eq!(explanation["no_run_guards"]["source_compilation"], false);
    assert_eq!(explanation["no_run_guards"]["source_scanning"], false);
    assert_eq!(explanation["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(explanation["no_run_guards"]["target_codegen"], false);
    assert!(explanation["runtime_service_boundaries"].is_null());
    assert!(explanation["runtime_bound_apis"].is_null());
}

#[test]
fn cli_diagnostics_explain_reports_no_run_guards_for_known_and_unknown_codes() {
    for code in ["LNC0017", "LNC9999"] {
        let mut command = Command::new(laniusc_bin());
        command.arg("diagnostics").arg("explain").arg(code);
        let output = command_output_with_timeout(
            "laniusc diagnostics explain no-run guard contract",
            &mut command,
            CLI_DIAGNOSTIC_TIMEOUT,
        )
        .expect("spawn laniusc diagnostics explain");

        assert!(
            output.status.success(),
            "diagnostics explain should be a successful no-run query for {code}\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            output.stderr.is_empty(),
            "diagnostics explain should not render a diagnostic for {code}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stderr)
        );

        let explanation: serde_json::Value =
            serde_json::from_slice(&output.stdout).expect("explain output should be JSON");
        assert_eq!(explanation["requested_code"], code);
        let expected_explain_command = format!("laniusc diagnostics explain {code}");
        assert_eq!(
            explanation["explain_command"].as_str(),
            Some(expected_explain_command.as_str())
        );
        assert_eq!(
            explanation["schema_version"],
            laniusc::compiler::DIAGNOSTIC_EXPLANATION_SCHEMA_VERSION
        );
        assert_eq!(
            explanation["schema_name"],
            laniusc::compiler::DIAGNOSTIC_EXPLANATION_SCHEMA_NAME
        );
        assert_eq!(explanation["no_run_guards"]["source_compilation"], false);
        assert_eq!(explanation["no_run_guards"]["source_scanning"], false);
        assert_eq!(explanation["no_run_guards"]["gpu_device_creation"], false);
        assert_eq!(explanation["no_run_guards"]["target_codegen"], false);
    }
}

#[test]
fn cli_diagnostics_explain_runtime_boundary_lists_fail_closed_services() {
    let mut command = Command::new(laniusc_bin());
    command.arg("diagnostics").arg("explain").arg("LNC0038");
    let output = command_output_with_timeout(
        "laniusc diagnostics explain LNC0038",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics explain LNC0038");

    assert!(
        output.status.success(),
        "runtime-service diagnostic explanation should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime-service diagnostic explanation should not print stderr\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let explanation: serde_json::Value = serde_json::from_slice(&output.stdout)
        .expect("runtime-service explanation output should be JSON");
    assert_eq!(
        explanation["schema_version"],
        laniusc::compiler::DIAGNOSTIC_EXPLANATION_SCHEMA_VERSION
    );
    assert_eq!(explanation["requested_code"], "LNC0038");
    assert_eq!(explanation["known"], true);
    assert_eq!(explanation["diagnostic"]["category"], "runtime binding");
    assert_eq!(
        explanation["unsupported_feature"]["boundary"],
        "runtime service binding"
    );
    let services = explanation["runtime_service_boundaries"]
        .as_array()
        .expect("LNC0038 explanation should include runtime service rows");
    assert_eq!(
        services.len(),
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.len()
    );
    assert_eq!(
        services
            .iter()
            .map(|service| service["service_id"]
                .as_u64()
                .expect("runtime service id should be numeric"))
            .collect::<Vec<_>>(),
        laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_IDS
            .iter()
            .map(|service_id| u64::from(*service_id))
            .collect::<Vec<_>>()
    );
    assert!(services.iter().any(|service| {
        service["service_id"].as_u64()
            == Some(u64::from(
                laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_TEST_HARNESS_ID,
            ))
            && service["module_path"] == "test::harness"
            && service["binding_probe"]
                .as_str()
                .is_some_and(|probe| !probe.trim().is_empty())
            && json_string_array_matches(
                service,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
            )
    }));
    assert!(services.iter().all(|service| {
        service["diagnostic_code"] == "LNC0038"
            && json_string_array_matches(
                service,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
            )
            && service["current_status"] == "known-unbound"
            && service["executable"] == false
    }));
    let apis = explanation["runtime_bound_apis"]
        .as_array()
        .expect("LNC0038 explanation should include runtime-bound API rows");
    assert_eq!(
        apis.len(),
        laniusc::compiler::RUNTIME_BOUND_API_DIAGNOSTICS.len()
    );
    assert!(apis.iter().any(|api| {
        api["api_name"] == "std::io::print_i32"
            && api["service_id"].as_u64()
                == Some(u64::from(
                    laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
                ))
            && api["service_module_path"] == "std::io"
            && api["service_current_status"] == "known-unbound"
            && api["service_executable"] == false
            && api["executable_probe"]
                .as_str()
                .is_some_and(|probe| !probe.trim().is_empty())
            && api["binding_probe"]
                .as_str()
                .is_some_and(|probe| !probe.trim().is_empty())
            && json_string_array_matches(
                api,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
            )
            && api["executable"] == false
    }));
    assert!(apis.iter().all(|api| {
        let service_id = api["service_id"]
            .as_u64()
            .and_then(|service_id| u32::try_from(service_id).ok());
        let service =
            service_id.and_then(laniusc::compiler::runtime_service_boundary_diagnostic_info);
        api["diagnostic_code"] == "LNC0038"
            && json_string_array_matches(
                api,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
            )
            && api["current_status"] == "known-unbound"
            && api["executable"] == false
            && service.is_some_and(|service| {
                api["service_capability_constant"] == service.capability_constant
                    && api["service_module_path"] == service.module_path
                    && api["service_status_probe"] == service.status_probe
                    && api["service_binding_probe"] == service.binding_probe
                    && api["service_current_status"] == service.current_status
                    && api["service_executable"] == service.executable
            })
    }));
}

#[test]
fn cli_diagnostics_runtime_api_reports_known_unbound_stdlib_api_without_source_scan() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-api")
        .arg("std::io::print_i32")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-api std::io::print_i32",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-api");

    assert!(
        output.status.success(),
        "runtime API diagnostic contract should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime API diagnostic contract should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("runtime API output should be JSON");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(document["schema_name"], "laniusc.diagnostics.runtime-api");
    assert_eq!(
        document["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(document["requested_api"], "std::io::print_i32");
    assert_eq!(document["known"], true);
    assert_eq!(document["matched_by"], "api_name");
    assert!(json_string_array_matches(
        &document,
        "accepted_selector_kinds",
        laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
    ));
    assert!(json_string_array_matches(
        &document,
        "service_accepted_selector_kinds",
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
    ));
    assert_eq!(document["canonical_api_name"], "std::io::print_i32");
    assert_eq!(document["diagnostic_code"], "LNC0038");
    assert_eq!(
        document["runtime_bound_api"]["api_name"],
        "std::io::print_i32"
    );
    assert_eq!(document["runtime_bound_api"]["module_path"], "std::io");
    assert_eq!(
        document["runtime_bound_api"]["service_id"].as_u64(),
        Some(u64::from(
            laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ))
    );
    assert_eq!(
        document["runtime_bound_api"]["service_current_status"],
        "known-unbound"
    );
    assert!(json_string_array_matches(
        &document["runtime_bound_api"],
        "accepted_selector_kinds",
        laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
    ));
    assert_eq!(document["runtime_bound_api"]["service_executable"], false);
    assert_eq!(
        document["runtime_bound_api"]["current_status"],
        "known-unbound"
    );
    assert_eq!(document["runtime_bound_api"]["executable"], false);
    assert_eq!(
        document["runtime_service_boundary"]["service_name"],
        "stdio"
    );
    assert_eq!(
        document["runtime_service_boundary"]["module_path"],
        "std::io"
    );
    assert_eq!(
        document["runtime_service_boundary"]["current_status"],
        "known-unbound"
    );
    assert!(json_string_array_matches(
        &document["runtime_service_boundary"],
        "accepted_selector_kinds",
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
    ));
    assert_eq!(document["runtime_service_boundary"]["executable"], false);
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
}

#[test]
fn cli_diagnostics_runtime_api_accepts_service_qualified_selector_without_source_scan() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-api")
        .arg("stdio::print_i32")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-api stdio::print_i32",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-api service-qualified selector");

    assert!(
        output.status.success(),
        "runtime API lookup by service-qualified selector should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime API lookup by service-qualified selector should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("runtime API output should be JSON");
    assert_eq!(document["schema_version"], 2);
    assert_eq!(document["schema_name"], "laniusc.diagnostics.runtime-api");
    assert_eq!(document["requested_api"], "stdio::print_i32");
    assert_eq!(document["known"], true);
    assert_eq!(document["matched_by"], "service_api_name");
    assert_eq!(document["canonical_api_name"], "std::io::print_i32");
    assert_eq!(
        document["runtime_bound_api"]["api_name"],
        "std::io::print_i32"
    );
    assert_eq!(document["runtime_bound_api"]["service_name"], "stdio");
    assert_eq!(
        document["runtime_service_boundary"]["service_id"].as_u64(),
        Some(u64::from(
            laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ))
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_api_accepts_copied_quoted_selector_without_source_scan() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-api")
        .arg("`stdio::print_i32`")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-api copied quoted selector",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-api copied selector");

    assert!(
        output.status.success(),
        "runtime API lookup by copied selector should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime API lookup by copied selector should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("runtime API output should be JSON");
    assert_eq!(document["schema_version"], 2);
    assert_eq!(document["schema_name"], "laniusc.diagnostics.runtime-api");
    assert_eq!(document["requested_api"], "stdio::print_i32");
    assert_eq!(document["known"], true);
    assert_eq!(document["matched_by"], "service_api_name");
    assert_eq!(document["canonical_api_name"], "std::io::print_i32");
    assert_eq!(document["diagnostic_code"], "LNC0038");
    assert_eq!(document["runtime_bound_api"]["service_name"], "stdio");
    assert_eq!(
        document["runtime_service_boundary"]["module_path"],
        "std::io"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_apis_prints_stdlib_runtime_api_index_without_source_scan() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-apis")
        .arg("--diagnostic-format=lsp-json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-apis",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-apis");

    assert!(
        output.status.success(),
        "runtime API diagnostic index should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime API diagnostic index should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("runtime API index should be JSON metadata");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(document["schema_name"], "laniusc.diagnostics.runtime-apis");
    assert_eq!(
        document["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(document["diagnostic_code"], "LNC0038");
    assert_eq!(
        document["explain_command"],
        "laniusc diagnostics explain LNC0038"
    );
    assert_eq!(
        document["runtime_api_query_command"],
        "laniusc diagnostics runtime-api API"
    );
    assert!(json_string_array_matches(
        &document,
        "accepted_selector_kinds",
        laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
    ));
    assert!(json_string_array_matches(
        &document,
        "service_accepted_selector_kinds",
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
    ));

    let apis = document["runtime_bound_apis"]
        .as_array()
        .expect("runtime API index should include API rows");
    assert_eq!(
        document["runtime_bound_api_count"],
        laniusc::compiler::RUNTIME_BOUND_API_DIAGNOSTICS.len()
    );
    assert_eq!(document["runtime_bound_api_count"], apis.len());
    assert!(apis.iter().any(|api| {
        api["api_name"] == "std::io::print_i32"
            && api["module_path"] == "std::io"
            && api["service_id"].as_u64()
                == Some(u64::from(
                    laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
                ))
            && api["diagnostic_code"] == "LNC0038"
            && json_string_array_matches(
                api,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
            )
            && api["current_status"] == "known-unbound"
            && api["executable"] == false
    }));
    assert!(apis.iter().all(|api| {
        api["diagnostic_code"] == "LNC0038"
            && json_string_array_matches(
                api,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
            )
            && api["service_current_status"] == "known-unbound"
            && api["service_executable"] == false
            && api["current_status"] == "known-unbound"
            && api["executable"] == false
    }));

    let services = document["runtime_service_boundaries"]
        .as_array()
        .expect("runtime API index should include service-boundary rows");
    assert_eq!(
        document["runtime_service_boundary_count"],
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.len()
    );
    assert_eq!(document["runtime_service_boundary_count"], services.len());
    assert!(services.iter().any(|service| {
        service["service_id"].as_u64()
            == Some(u64::from(
                laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            ))
            && service["service_name"] == "stdio"
            && service["module_path"] == "std::io"
            && service["diagnostic_code"] == "LNC0038"
            && json_string_array_matches(
                service,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
            )
            && service["current_status"] == "known-unbound"
            && service["executable"] == false
    }));
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_services_prints_stdlib_runtime_service_index_without_source_scan() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-services")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-services",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-services");

    assert!(
        output.status.success(),
        "runtime service diagnostic index should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime service diagnostic index should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value = serde_json::from_slice(&output.stdout)
        .expect("runtime service index should be JSON metadata");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.runtime-services"
    );
    assert_eq!(
        document["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(document["diagnostic_code"], "LNC0038");
    assert_eq!(
        document["explain_command"],
        "laniusc diagnostics explain LNC0038"
    );
    assert_eq!(
        document["runtime_api_index_command"],
        "laniusc diagnostics runtime-apis"
    );

    let services = document["runtime_service_boundaries"]
        .as_array()
        .expect("runtime service index should include service-boundary rows");
    assert_eq!(
        document["runtime_service_boundary_count"],
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.len()
    );
    assert_eq!(document["runtime_service_boundary_count"], services.len());
    assert!(services.iter().any(|service| {
        service["service_id"].as_u64()
            == Some(u64::from(
                laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            ))
            && service["service_name"] == "stdio"
            && service["module_path"] == "std::io"
            && service["capability_constant"] == "STDIO_HAS_RUNTIME_BINDING"
            && service["status_probe"] == "stdio_service_status()"
            && service["binding_probe"] == "stdio_requires_runtime_binding()"
            && json_string_array_matches(
                service,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
            )
            && service["current_status"] == "known-unbound"
            && service["executable"] == false
    }));
    assert!(services.iter().all(|service| {
        service["diagnostic_code"] == "LNC0038"
            && json_string_array_matches(
                service,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
            )
            && service["current_status"] == "known-unbound"
            && service["executable"] == false
            && service["module_path"]
                .as_str()
                .is_some_and(|path| !path.trim().is_empty())
            && service["capability_constant"]
                .as_str()
                .is_some_and(|constant| !constant.trim().is_empty())
            && service["status_probe"]
                .as_str()
                .is_some_and(|probe| !probe.trim().is_empty())
            && service["binding_probe"]
                .as_str()
                .is_some_and(|probe| !probe.trim().is_empty())
    }));
    assert!(
        document.get("runtime_bound_apis").is_none(),
        "service-only discovery should not require wrappers to parse API rows"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_service_reports_stdlib_service_by_module_path_without_source_scan() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-service")
        .arg("std::io")
        .arg("--diagnostic-format=lsp-json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-service std::io",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-service");

    assert!(
        output.status.success(),
        "runtime service diagnostic contract should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime service diagnostic contract should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("runtime service output should be JSON");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.runtime-service"
    );
    assert_eq!(
        document["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(document["requested_service"], "std::io");
    assert_eq!(document["known"], true);
    assert_eq!(document["matched_by"], "module_path");
    assert!(json_string_array_matches(
        &document,
        "accepted_selector_kinds",
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
    ));
    assert!(json_string_array_matches(
        &document,
        "runtime_api_accepted_selector_kinds",
        laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
    ));
    assert_eq!(document["diagnostic_code"], "LNC0038");
    assert_eq!(
        document["runtime_service_boundary"]["service_id"].as_u64(),
        Some(u64::from(
            laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ))
    );
    assert_eq!(
        document["runtime_service_boundary"]["service_name"],
        "stdio"
    );
    assert_eq!(
        document["runtime_service_boundary"]["module_path"],
        "std::io"
    );
    assert_eq!(
        document["runtime_service_boundary"]["capability_constant"],
        "STDIO_HAS_RUNTIME_BINDING"
    );
    assert_eq!(
        document["runtime_service_boundary"]["current_status"],
        "known-unbound"
    );
    assert!(json_string_array_matches(
        &document["runtime_service_boundary"],
        "accepted_selector_kinds",
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
    ));
    assert_eq!(document["runtime_service_boundary"]["executable"], false);
    assert_eq!(
        document["runtime_api_index_command"],
        "laniusc diagnostics runtime-apis"
    );
    assert_eq!(
        document["runtime_service_index_command"],
        "laniusc diagnostics runtime-services"
    );
    assert!(
        document.get("runtime_bound_apis").is_none(),
        "single-service lookup should not require wrappers to parse API rows"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_service_accepts_service_qualified_api_selector_without_source_scan() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-service")
        .arg("stdio::print_i32")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-service stdio::print_i32",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-service with service-qualified API selector");

    assert!(
        output.status.success(),
        "runtime service lookup by service-qualified API should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime service lookup by service-qualified API should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value = serde_json::from_slice(&output.stdout)
        .expect("runtime service selector output should be JSON");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.runtime-service"
    );
    assert_eq!(document["requested_service"], "stdio::print_i32");
    assert_eq!(document["known"], true);
    assert_eq!(document["matched_by"], "service_api_name");
    assert_eq!(document["diagnostic_code"], "LNC0038");
    assert_eq!(
        document["runtime_service_boundary"]["service_id"].as_u64(),
        Some(u64::from(
            laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ))
    );
    assert_eq!(
        document["runtime_service_boundary"]["service_name"],
        "stdio"
    );
    assert_eq!(
        document["runtime_service_boundary"]["module_path"],
        "std::io"
    );
    assert_eq!(
        document["runtime_service_boundary"]["current_status"],
        "known-unbound"
    );
    assert_eq!(document["runtime_service_boundary"]["executable"], false);
    assert!(
        document.get("runtime_bound_apis").is_none(),
        "single-service lookup should not require wrappers to parse API rows"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_service_accepts_copied_quoted_selector_without_source_scan() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-service")
        .arg("\"stdio_requires_runtime_binding()\"")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-service copied quoted selector",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-service copied selector");

    assert!(
        output.status.success(),
        "runtime service lookup by copied selector should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime service lookup by copied selector should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("runtime service output should be JSON");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.runtime-service"
    );
    assert_eq!(
        document["requested_service"],
        "stdio_requires_runtime_binding()"
    );
    assert_eq!(document["known"], true);
    assert_eq!(document["matched_by"], "binding_probe");
    assert_eq!(document["diagnostic_code"], "LNC0038");
    assert_eq!(
        document["runtime_service_boundary"]["module_path"],
        "std::io"
    );
    assert_eq!(
        document["runtime_service_boundary"]["binding_probe"],
        "stdio_requires_runtime_binding()"
    );
    assert_eq!(document["runtime_service_boundary"]["executable"], false);
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_service_apis_reports_service_api_rows_without_source_scan() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-service-apis")
        .arg("stdio")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-service-apis stdio",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-service-apis");

    assert!(
        output.status.success(),
        "runtime service API diagnostic contract should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime service API diagnostic contract should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("runtime service API output should be JSON");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.runtime-service-apis"
    );
    assert_eq!(
        document["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(document["requested_service"], "stdio");
    assert_eq!(document["known"], true);
    assert_eq!(document["matched_by"], "service_name");
    assert!(json_string_array_matches(
        &document,
        "accepted_selector_kinds",
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
    ));
    assert!(json_string_array_matches(
        &document,
        "runtime_api_accepted_selector_kinds",
        laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
    ));
    assert_eq!(document["diagnostic_code"], "LNC0038");
    assert_eq!(
        document["runtime_service_boundary"]["service_id"].as_u64(),
        Some(u64::from(
            laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ))
    );
    assert_eq!(
        document["runtime_service_boundary"]["module_path"],
        "std::io"
    );

    let apis = document["runtime_bound_apis"]
        .as_array()
        .expect("runtime service API lookup should include API rows");
    let expected_stdio_api_count = laniusc::compiler::RUNTIME_BOUND_API_DIAGNOSTICS
        .iter()
        .filter(|api| api.service_id == laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID)
        .count();
    assert_eq!(
        document["runtime_bound_api_count"],
        expected_stdio_api_count
    );
    assert_eq!(apis.len(), expected_stdio_api_count);
    assert!(apis.iter().all(|api| {
        api["service_id"].as_u64()
            == Some(u64::from(
                laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            ))
            && api["service_name"] == "stdio"
            && api["service_module_path"] == "std::io"
            && api["diagnostic_code"] == "LNC0038"
            && json_string_array_matches(
                api,
                "accepted_selector_kinds",
                laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
            )
            && api["service_current_status"] == "known-unbound"
            && api["service_executable"] == false
            && api["current_status"] == "known-unbound"
            && api["executable"] == false
    }));
    assert!(
        apis.iter().any(|api| {
            api["api_name"] == "std::io::print_i32" && api["module_path"] == "std::io"
        })
    );
    assert_eq!(
        document["runtime_api_index_command"],
        "laniusc diagnostics runtime-apis"
    );
    assert_eq!(
        document["runtime_service_query_command"],
        "laniusc diagnostics runtime-service SERVICE"
    );
    assert_eq!(
        document["runtime_service_index_command"],
        "laniusc diagnostics runtime-services"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_service_apis_accepts_capability_constant_selector_without_source_scan() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-service-apis")
        .arg("STDIO_HAS_RUNTIME_BINDING")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-service-apis STDIO_HAS_RUNTIME_BINDING",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-service-apis with capability selector");

    assert!(
        output.status.success(),
        "runtime service API lookup by capability constant should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime service API lookup by capability constant should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value = serde_json::from_slice(&output.stdout)
        .expect("runtime service API selector output should be JSON");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.runtime-service-apis"
    );
    assert_eq!(document["requested_service"], "STDIO_HAS_RUNTIME_BINDING");
    assert_eq!(document["known"], true);
    assert_eq!(document["matched_by"], "capability_constant");
    assert_eq!(
        document["runtime_service_boundary"]["service_id"].as_u64(),
        Some(u64::from(
            laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ))
    );
    assert_eq!(
        document["runtime_service_boundary"]["capability_constant"],
        "STDIO_HAS_RUNTIME_BINDING"
    );

    let apis = document["runtime_bound_apis"]
        .as_array()
        .expect("capability selector should return service API rows");
    assert!(
        apis.iter().any(|api| {
            api["api_name"] == "std::io::print_i32"
                && api["service_id"].as_u64()
                    == Some(u64::from(
                        laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
                    ))
                && api["service_capability_constant"] == "STDIO_HAS_RUNTIME_BINDING"
        }),
        "capability selector should expose the stdio runtime-bound API rows"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_service_apis_accepts_qualified_api_selector_without_source_scan() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-service-apis")
        .arg("std::io::print_i32")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-service-apis std::io::print_i32",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-service-apis with API selector");

    assert!(
        output.status.success(),
        "runtime service API lookup by qualified API should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime service API lookup by qualified API should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value = serde_json::from_slice(&output.stdout)
        .expect("runtime service API selector output should be JSON");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.runtime-service-apis"
    );
    assert_eq!(document["requested_service"], "std::io::print_i32");
    assert_eq!(document["known"], true);
    assert_eq!(document["matched_by"], "api_name");
    assert_eq!(document["diagnostic_code"], "LNC0038");
    assert_eq!(
        document["runtime_service_boundary"]["service_id"].as_u64(),
        Some(u64::from(
            laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ))
    );
    assert_eq!(
        document["runtime_service_boundary"]["module_path"],
        "std::io"
    );

    let apis = document["runtime_bound_apis"]
        .as_array()
        .expect("qualified API selector should return service API rows");
    let expected_stdio_api_count = laniusc::compiler::RUNTIME_BOUND_API_DIAGNOSTICS
        .iter()
        .filter(|api| api.service_id == laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID)
        .count();
    assert_eq!(
        document["runtime_bound_api_count"],
        expected_stdio_api_count
    );
    assert_eq!(apis.len(), expected_stdio_api_count);
    assert!(
        apis.iter().any(|api| {
            api["api_name"] == "std::io::print_i32"
                && api["service_module_path"] == "std::io"
                && api["diagnostic_code"] == "LNC0038"
                && api["service_current_status"] == "known-unbound"
                && api["executable"] == false
        }),
        "qualified API selector should expose the selected API row"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_service_apis_accepts_service_qualified_api_selector_without_source_scan()
{
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-service-apis")
        .arg("stdio::print_i32")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-service-apis stdio::print_i32",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-service-apis with service-qualified API selector");

    assert!(
        output.status.success(),
        "runtime service API lookup by service-qualified API should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "runtime service API lookup by service-qualified API should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value = serde_json::from_slice(&output.stdout)
        .expect("runtime service API selector output should be JSON");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.runtime-service-apis"
    );
    assert_eq!(document["requested_service"], "stdio::print_i32");
    assert_eq!(document["known"], true);
    assert_eq!(document["matched_by"], "service_api_name");
    assert_eq!(document["diagnostic_code"], "LNC0038");
    assert_eq!(
        document["runtime_service_boundary"]["service_id"].as_u64(),
        Some(u64::from(
            laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ))
    );
    assert_eq!(
        document["runtime_service_boundary"]["module_path"],
        "std::io"
    );

    let apis = document["runtime_bound_apis"]
        .as_array()
        .expect("service-qualified API selector should return service API rows");
    let expected_stdio_api_count = laniusc::compiler::RUNTIME_BOUND_API_DIAGNOSTICS
        .iter()
        .filter(|api| api.service_id == laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID)
        .count();
    assert_eq!(
        document["runtime_bound_api_count"],
        expected_stdio_api_count
    );
    assert_eq!(apis.len(), expected_stdio_api_count);
    assert!(
        apis.iter().any(|api| {
            api["api_name"] == "std::io::print_i32"
                && api["service_name"] == "stdio"
                && api["service_module_path"] == "std::io"
                && api["diagnostic_code"] == "LNC0038"
                && api["current_status"] == "known-unbound"
                && api["executable"] == false
        }),
        "service-qualified API selector should expose the selected API row"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_api_reports_unknown_api_as_no_run_result() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-api")
        .arg("std::io::println");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-api std::io::println",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-api unknown API");

    assert!(
        output.status.success(),
        "unknown runtime API query should stay machine-readable instead of becoming a diagnostic\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "unknown runtime API query should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("runtime API output should be JSON");
    assert_eq!(document["schema_version"], 2);
    assert_eq!(document["schema_name"], "laniusc.diagnostics.runtime-api");
    assert_eq!(document["requested_api"], "std::io::println");
    assert_eq!(document["known"], false);
    assert!(document["matched_by"].is_null());
    assert!(json_string_array_matches(
        &document,
        "accepted_selector_kinds",
        laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
    ));
    assert!(json_string_array_matches(
        &document,
        "service_accepted_selector_kinds",
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
    ));
    assert_eq!(
        document["selector_examples"]["api_name"],
        "std::io::print_i32"
    );
    assert_eq!(
        document["selector_examples"]["service_api_name"],
        "stdio::print_i32"
    );
    assert_eq!(
        document["runtime_api_index_command"],
        "laniusc diagnostics runtime-apis"
    );
    assert_eq!(
        document["runtime_service_index_command"],
        "laniusc diagnostics runtime-services"
    );
    assert!(document["canonical_api_name"].is_null());
    assert!(document["diagnostic_code"].is_null());
    assert!(document["runtime_bound_api"].is_null());
    assert!(document["runtime_service_boundary"].is_null());
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
}

#[test]
fn cli_diagnostics_runtime_service_reports_unknown_selector_as_no_run_result() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-service")
        .arg("std::io::println")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-service std::io::println",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-service unknown selector");

    assert!(
        output.status.success(),
        "unknown runtime service selector should stay machine-readable instead of becoming a diagnostic\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "unknown runtime service selector should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("runtime service output should be JSON");
    assert_eq!(document["schema_version"], 1);
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.runtime-service"
    );
    assert_eq!(document["requested_service"], "std::io::println");
    assert_eq!(document["known"], false);
    assert!(document["matched_by"].is_null());
    assert!(json_string_array_matches(
        &document,
        "accepted_selector_kinds",
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
    ));
    assert!(json_string_array_matches(
        &document,
        "runtime_api_accepted_selector_kinds",
        laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
    ));
    assert_eq!(
        document["selector_examples"]["service_id"].as_u64(),
        Some(u64::from(
            laniusc::compiler::GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ))
    );
    assert_eq!(document["selector_examples"]["service_name"], "stdio");
    assert_eq!(document["selector_examples"]["module_path"], "std::io");
    assert_eq!(
        document["selector_examples"]["capability_constant"],
        "STDIO_HAS_RUNTIME_BINDING"
    );
    assert_eq!(
        document["selector_examples"]["status_probe"],
        "stdio_service_status()"
    );
    assert_eq!(
        document["selector_examples"]["binding_probe"],
        "stdio_requires_runtime_binding()"
    );
    assert_eq!(
        document["selector_examples"]["api_name"],
        "std::io::print_i32"
    );
    assert_eq!(
        document["selector_examples"]["service_api_name"],
        "stdio::print_i32"
    );
    assert!(document["diagnostic_code"].is_null());
    assert!(document["runtime_service_boundary"].is_null());
    assert_eq!(
        document["runtime_api_index_command"],
        "laniusc diagnostics runtime-apis"
    );
    assert_eq!(
        document["runtime_service_index_command"],
        "laniusc diagnostics runtime-services"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert!(
        document.get("source").is_none(),
        "unknown metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_runtime_service_apis_reports_unknown_selector_as_no_run_result() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("runtime-service-apis")
        .arg("std::io::println")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics runtime-service-apis unknown selector",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics runtime-service-apis unknown selector");

    assert!(
        output.status.success(),
        "unknown runtime service API selector should still be a successful metadata query\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "unknown runtime service API selector should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value = serde_json::from_slice(&output.stdout)
        .expect("unknown runtime service API selector output should be JSON");
    assert_eq!(
        document["schema_name"],
        "laniusc.diagnostics.runtime-service-apis"
    );
    assert_eq!(document["requested_service"], "std::io::println");
    assert_eq!(document["known"], false);
    assert!(document["matched_by"].is_null());
    assert!(document["diagnostic_code"].is_null());
    assert!(document["runtime_service_boundary"].is_null());
    assert_eq!(document["runtime_bound_api_count"], 0);
    assert!(
        document["runtime_bound_apis"]
            .as_array()
            .is_some_and(|apis| apis.is_empty()),
        "unknown selector should not fabricate runtime API rows\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    assert!(json_string_array_matches(
        &document,
        "accepted_selector_kinds",
        laniusc::compiler::RUNTIME_SERVICE_BOUNDARY_SELECTOR_KINDS,
    ));
    assert!(json_string_array_matches(
        &document,
        "runtime_api_accepted_selector_kinds",
        laniusc::compiler::RUNTIME_BOUND_API_SELECTOR_KINDS,
    ));
    assert_eq!(
        document["runtime_api_index_command"],
        "laniusc diagnostics runtime-apis"
    );
    assert_eq!(
        document["runtime_service_query_command"],
        "laniusc diagnostics runtime-service SERVICE"
    );
    assert_eq!(
        document["runtime_service_index_command"],
        "laniusc diagnostics runtime-services"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["stdlib_source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
}

#[test]
fn cli_diagnostics_explain_missing_code_can_render_json_diagnostic() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("explain")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics explain JSON missing code diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics explain");

    assert!(
        !output.status.success(),
        "diagnostics explain without a code should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "missing diagnostics explain code should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(
        diagnostic["schema_version"],
        laniusc::compiler::DIAGNOSTIC_JSON_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0026");
    assert_eq!(diagnostic["title"], "missing CLI argument");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["primary_label_policy"], "none");
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0026"
    );
    assert_eq!(diagnostic["message"], "missing CLI argument");
    assert!(diagnostic["primary_label"].is_null());
    assert!(
        diagnostic["help"].as_str().is_some_and(|help| {
            help.contains("laniusc diagnostics explain --help") && help.contains("diagnostic code")
        }),
        "missing diagnostics explain code should expose public recovery help\nstderr:\n{stderr}"
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("missing diagnostics explain code should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc diagnostics explain")),
        "diagnostic notes should identify the diagnostics explain command\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("diagnostic code")),
        "diagnostic notes should describe the required argument\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_diagnostics_explain_reports_unknown_code_as_machine_readable_result() {
    let mut command = Command::new(laniusc_bin());
    command.arg("diagnostics").arg("explain").arg(" lnc9999 ");
    let output = command_output_with_timeout(
        "laniusc diagnostics explain canonicalized unknown code",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics explain unknown code");

    assert!(
        output.status.success(),
        "unknown diagnostic explanation should still be a successful query\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "unknown diagnostic explanation should not print text diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let explanation: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("unknown explain output should be JSON");
    assert_eq!(
        explanation["schema_version"],
        laniusc::compiler::DIAGNOSTIC_EXPLANATION_SCHEMA_VERSION
    );
    assert_eq!(
        explanation["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(explanation["requested_code"], "LNC9999");
    assert_eq!(
        explanation["explain_command"],
        "laniusc diagnostics explain LNC9999"
    );
    assert_eq!(explanation["known"], false);
    assert!(explanation["diagnostic"].is_null());
    assert!(explanation["unsupported_feature"].is_null());
    assert!(explanation["runtime_service_boundaries"].is_null());
    assert!(explanation["runtime_bound_apis"].is_null());
    assert_eq!(
        json_string_array(&explanation, "accepted_selector_examples").as_slice(),
        laniusc::compiler::DIAGNOSTIC_CODE_SELECTOR_EXAMPLES
    );
    assert_eq!(
        json_string_array(&explanation, "accepted_selector_patterns").as_slice(),
        laniusc::compiler::DIAGNOSTIC_CODE_SELECTOR_PATTERNS
    );
    assert_eq!(
        explanation["code_index_command"],
        laniusc::compiler::DIAGNOSTIC_CODE_INDEX_COMMAND
    );
    assert_eq!(
        explanation["registry_command"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_COMMAND
    );
}

#[test]
fn cli_diagnostics_unknown_subcommand_can_render_json_diagnostic() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("--diagnostic-format=json")
        .arg("unknown");
    let output = command_output_with_timeout(
        "laniusc diagnostics JSON unknown subcommand diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics");

    assert!(
        !output.status.success(),
        "unknown diagnostics subcommand should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "unknown diagnostics subcommand should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0039");
    assert_eq!(diagnostic["title"], "unknown CLI subcommand");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unknown CLI subcommand");
    assert!(diagnostic["primary_label"].is_null());
    assert!(
        diagnostic["help"]
            .as_str()
            .is_some_and(|help| help.contains("laniusc diagnostics --help")),
        "unknown diagnostics subcommand should expose public recovery help\nstderr:\n{stderr}"
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("unknown diagnostics subcommand should include notes");
    let notes_text = notes
        .iter()
        .map(|note| note.as_str().expect("diagnostic note should be a string"))
        .collect::<Vec<_>>()
        .join("\n");
    assert!(
        notes_text.contains("laniusc diagnostics"),
        "diagnostic notes should identify the diagnostics command\nstderr:\n{stderr}"
    );
    assert!(
        notes_text.contains("registry") && notes_text.contains("source-pack-progress"),
        "diagnostic notes should list accepted diagnostics subcommands\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_doctor_extra_argument_can_render_json_diagnostic_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("doctor")
        .arg("--diagnostic-format=json")
        .arg("unexpected-input.lani");
    let output = command_output_with_timeout(
        "laniusc doctor JSON unexpected argument diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc doctor");

    assert!(
        !output.status.success(),
        "unexpected doctor argument should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "unexpected doctor argument should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0031");
    assert_eq!(diagnostic["title"], "unexpected CLI argument");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unexpected CLI argument");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("unexpected argument diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc doctor")),
        "diagnostic notes should identify the doctor command\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("unexpected-input.lani")),
        "diagnostic notes should include the unexpected argument\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_fmt_stdin_check_can_render_lsp_json_diagnostic_without_stdout_rewrite() {
    let source = "fn main(){return 0;}\n";
    let mut command = Command::new(laniusc_bin());
    command
        .arg("fmt")
        .arg("--stdin")
        .arg("--check")
        .arg("--diagnostic-format=lsp-json");
    let output = command_output_with_stdin_timeout(
        "laniusc fmt stdin LSP JSON check diagnostic",
        &mut command,
        source,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc fmt");

    assert!(
        !output.status.success(),
        "unformatted stdin should fail --check\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "fmt --stdin --check should not print the rewrite on failure\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "LSP JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one LSP diagnostic object");
    assert_eq!(diagnostic["severity"], 1);
    assert_eq!(diagnostic["code"], "LNC0019");
    assert_eq!(diagnostic["source"], "laniusc");
    assert_eq!(diagnostic["message"], "formatter check failed");
    assert_eq!(
        diagnostic["data"]["schema_version"],
        laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["data"]["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(diagnostic["data"]["position_encoding"], "utf-16");
    assert_eq!(diagnostic["data"]["title"], "formatter check failed");
    assert_eq!(diagnostic["data"]["category"], "tooling");
    assert_eq!(diagnostic["data"]["primary_label_policy"], "required");
    assert_eq!(
        diagnostic["data"]["explain_command"],
        "laniusc diagnostics explain LNC0019"
    );
    assert_eq!(diagnostic["data"]["primary_label"]["path"], "<stdin>");
    assert_eq!(diagnostic["data"]["primary_label"]["line"], 1);
    assert!(
        diagnostic["data"]["primary_label"]
            .get("source_line")
            .is_none(),
        "LSP JSON formatter diagnostics should stay snippet-free\nstderr:\n{stderr}"
    );
    assert!(diagnostic["data"]["primary_label"]["column"].is_number());
    assert!(diagnostic["data"]["primary_label"]["length"].is_number());
    assert!(diagnostic["range"]["start"]["line"].is_number());
    assert!(diagnostic["range"]["start"]["character"].is_number());
    assert!(diagnostic["range"]["end"]["line"].is_number());
    assert!(diagnostic["range"]["end"]["character"].is_number());

    let notes = diagnostic["data"]["notes"]
        .as_array()
        .expect("LSP formatter diagnostic data should carry notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("<stdin>")),
        "formatter diagnostic notes should identify stdin\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc fmt --stdin")),
        "formatter diagnostic notes should include the stdin rewrite command\nstderr:\n{stderr}"
    );
    assert!(diagnostic.get("primary_label").is_none());
    assert!(diagnostic.get("notes").is_none());
    assert!(diagnostic.get("diagnostics").is_none());
}

#[test]
fn cli_fmt_stdin_invalid_utf8_can_render_json_diagnostic_without_stdout() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("fmt")
        .arg("--stdin")
        .arg("--diagnostic-format=json");
    let output = command_output_with_stdin_bytes_timeout(
        "laniusc fmt stdin invalid UTF-8 JSON diagnostic",
        &mut command,
        &[0xff, b'f', b'n'],
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc fmt");

    assert!(
        !output.status.success(),
        "invalid UTF-8 formatter stdin should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "invalid formatter stdin should not write formatted stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one diagnostic JSON object");
    assert_eq!(
        diagnostic["schema_version"],
        laniusc::compiler::DIAGNOSTIC_JSON_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0040");
    assert_eq!(diagnostic["title"], "input read failed");
    assert_eq!(diagnostic["message"], "input read failed");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["primary_label_policy"], "required");
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0040"
    );
    assert_eq!(diagnostic["primary_label"]["path"], "<stdin>");
    assert_eq!(diagnostic["primary_label"]["line"], 1);
    assert_eq!(diagnostic["primary_label"]["column"], 1);
    assert_eq!(diagnostic["primary_label"]["length"], 1);
    assert!(diagnostic["primary_label"]["source_line"].is_null());

    let notes = diagnostic["notes"]
        .as_array()
        .expect("stdin input-read diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("<stdin>")),
        "diagnostic notes should identify stdin\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("read formatter stdin")),
        "diagnostic notes should identify the stdin read operation\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("InvalidData")),
        "diagnostic notes should expose the public I/O error kind\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("UTF-8")),
        "diagnostic notes should include a UTF-8 remediation\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_fmt_missing_input_can_render_json_diagnostic_without_stdout() {
    let missing_input =
        common::temp_artifact_path("laniusc_cli_diagnostics", "fmt_missing_input", Some("lani"));
    let _ = fs::remove_file(&missing_input);

    let mut command = Command::new(laniusc_bin());
    command
        .arg("fmt")
        .arg("--diagnostic-format=json")
        .arg(&missing_input);
    let output = command_output_with_timeout(
        "laniusc fmt missing input JSON diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc fmt");

    assert!(
        !output.status.success(),
        "missing formatter input should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "missing formatter input should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one diagnostic JSON object");
    assert_eq!(
        diagnostic["schema_version"],
        laniusc::compiler::DIAGNOSTIC_JSON_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0040");
    assert_eq!(diagnostic["title"], "input read failed");
    assert_eq!(diagnostic["message"], "input read failed");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["primary_label_policy"], "required");
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0040"
    );
    assert_eq!(
        diagnostic["primary_label"]["path"],
        missing_input.to_string_lossy().as_ref()
    );
    assert_eq!(diagnostic["primary_label"]["line"], 1);
    assert_eq!(diagnostic["primary_label"]["column"], 1);
    assert_eq!(diagnostic["primary_label"]["length"], 1);
    assert!(diagnostic["primary_label"]["source_line"].is_null());

    let notes = diagnostic["notes"]
        .as_array()
        .expect("input-read diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("formatter input path")),
        "diagnostic notes should identify the input path\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("I/O error kind")),
        "diagnostic notes should include the I/O error kind\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--stdin")),
        "diagnostic notes should include a stdin recovery path\nstderr:\n{stderr}"
    );
}

#[cfg(unix)]
#[test]
fn cli_fmt_readonly_file_can_render_json_output_write_diagnostic_without_stdout() {
    use std::os::unix::fs::PermissionsExt;

    let root = common::temp_artifact_path("laniusc_cli_diagnostics", "fmt_readonly_output", None);
    fs::create_dir_all(&root).expect("create fmt readonly-output temp root");
    let input = root.join("readonly.lani");
    let source = "fn main(){return 0;}\n";
    fs::write(&input, source).expect("write readonly fmt input");

    let mut readonly = fs::metadata(&input)
        .expect("stat readonly fmt input")
        .permissions();
    readonly.set_mode(0o444);
    fs::set_permissions(&input, readonly).expect("make fmt input readonly");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("fmt")
        .arg("--diagnostic-format=json")
        .arg(&input);
    let output = command_output_with_timeout(
        "laniusc fmt readonly output JSON diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc fmt");

    let mut writable = fs::metadata(&input)
        .expect("stat readonly fmt input after command")
        .permissions();
    writable.set_mode(0o644);
    fs::set_permissions(&input, writable).expect("restore fmt input permissions");

    assert!(
        !output.status.success(),
        "readonly formatter output should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "readonly formatter output should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );
    assert_eq!(
        fs::read_to_string(&input).expect("read readonly fmt input after failed rewrite"),
        source,
        "failed formatter rewrite must leave the source file unchanged"
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one diagnostic JSON object");
    assert_eq!(
        diagnostic["schema_version"],
        laniusc::compiler::DIAGNOSTIC_JSON_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0034");
    assert_eq!(diagnostic["title"], "output write failed");
    assert_eq!(diagnostic["message"], "output write failed");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["primary_label_policy"], "required");
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0034"
    );
    assert_eq!(
        diagnostic["primary_label"]["path"],
        input.to_string_lossy().as_ref()
    );
    assert_eq!(diagnostic["primary_label"]["line"], 1);
    assert_eq!(diagnostic["primary_label"]["column"], 1);
    assert_eq!(diagnostic["primary_label"]["length"], 1);
    assert!(diagnostic["primary_label"]["source_line"].is_null());
    assert!(
        diagnostic["help"]
            .as_str()
            .expect("formatter output diagnostic should include recovery help")
            .contains("fmt --check"),
        "formatter output diagnostic should offer a no-rewrite recovery path\nstderr:\n{stderr}"
    );

    let notes = diagnostic["notes"]
        .as_array()
        .expect("output-write diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("formatter output path")),
        "diagnostic notes should identify the formatter output path\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("write formatter output")),
        "diagnostic notes should identify the formatter write operation\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("I/O error kind")),
        "diagnostic notes should include the I/O error kind\nstderr:\n{stderr}"
    );

    fs::remove_dir_all(&root).expect("remove fmt readonly-output temp root");
}

#[test]
fn cli_fmt_multiple_inputs_formats_each_file_without_diagnostics() {
    let root = common::temp_artifact_path("laniusc_cli_diagnostics", "fmt_multiple_inputs", None);
    fs::create_dir_all(&root).expect("create fmt multiple-input temp root");
    let first = root.join("first.lani");
    let second = root.join("second.lani");
    let first_source = "fn main(){return 7;}\n";
    let second_source = "fn helper(){let x=1;return x;}\n";
    fs::write(&first, first_source).expect("write first fmt input");
    fs::write(&second, second_source).expect("write second fmt input");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("fmt")
        .arg("--diagnostic-format=json")
        .arg(&first)
        .arg(&second);
    let output = command_output_with_timeout(
        "laniusc fmt multiple input files",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc fmt");

    assert!(
        output.status.success(),
        "multiple fmt inputs should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "fmt file mode should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );
    assert!(
        output.stderr.is_empty(),
        "successful fmt file mode should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    assert_eq!(
        fs::read_to_string(&first).expect("read formatted first input"),
        laniusc::formatter::format_source(first_source)
    );
    assert_eq!(
        fs::read_to_string(&second).expect("read formatted second input"),
        laniusc::formatter::format_source(second_source)
    );
    fs::remove_dir_all(&root).expect("remove fmt multiple-input temp root");
}

#[test]
fn cli_lsp_unknown_subcommand_can_render_json_diagnostic() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("lsp")
        .arg("--diagnostic-format=json")
        .arg("publish");
    let output = command_output_with_timeout(
        "laniusc lsp JSON unknown subcommand diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc lsp");

    assert!(
        !output.status.success(),
        "unknown lsp subcommand should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "unknown lsp subcommand should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0039");
    assert_eq!(diagnostic["title"], "unknown CLI subcommand");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unknown CLI subcommand");
    assert!(diagnostic["primary_label"].is_null());
    assert!(
        diagnostic["help"]
            .as_str()
            .is_some_and(|help| help.contains("laniusc lsp --help")),
        "unknown lsp subcommand should expose public recovery help\nstderr:\n{stderr}"
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("unknown lsp subcommand should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc lsp")),
        "diagnostic notes should identify the lsp command\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("capabilities")),
        "diagnostic notes should list accepted lsp subcommands\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_unsupported_emit_target_can_render_json_diagnostic_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=json")
        .arg("--emit")
        .arg("not-a-target");
    let output = command_output_with_timeout(
        "laniusc JSON unsupported emit target diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "unsupported emit target should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "unsupported emit target should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0018");
    assert_eq!(diagnostic["title"], "unsupported CLI option value");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unsupported CLI option value");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("CLI option diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--emit")),
        "diagnostic notes should identify the option\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("x86_64, wasm")),
        "diagnostic notes should list accepted emit values\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_missing_emit_value_can_render_json_diagnostic_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command.arg("--diagnostic-format=json").arg("--emit");
    let output = command_output_with_timeout(
        "laniusc JSON missing emit value diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "missing emit value should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "missing emit value should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0023");
    assert_eq!(diagnostic["title"], "missing CLI option value");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "missing CLI option value");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("missing value diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--emit")),
        "diagnostic notes should identify the option\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("x86_64, wasm")),
        "diagnostic notes should list accepted emit values\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_check_output_flag_can_render_json_incompatible_options_without_loading_input() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg("--diagnostic-format=json")
        .arg("-o")
        .arg("out.wasm");
    let output = command_output_with_timeout(
        "laniusc check JSON incompatible output option diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc check");

    assert!(
        !output.status.success(),
        "check mode with output should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "incompatible check output option should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0032");
    assert_eq!(diagnostic["title"], "incompatible CLI options");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "incompatible CLI options");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("incompatible options diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc check")),
        "diagnostic notes should identify the command\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("-o/--out")),
        "diagnostic notes should identify the incompatible output option\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_check_missing_input_can_render_json_diagnostic_without_loading_source() {
    let mut command = Command::new(laniusc_bin());
    command.arg("check").arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc check JSON missing input diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc check");

    assert!(
        !output.status.success(),
        "check mode without an input should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "missing check input should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0026");
    assert_eq!(diagnostic["title"], "missing CLI argument");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "missing CLI argument");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("missing check input diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc check")),
        "diagnostic notes should identify the check command\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--package-manifest")),
        "diagnostic notes should describe alternate package metadata inputs\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_source_pack_manifest_conflict_can_render_json_incompatible_options_without_loading_inputs() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=json")
        .arg("--source-pack-manifest")
        .arg("pack.json")
        .arg("--source-pack-library-manifest")
        .arg("library.json");
    let output = command_output_with_timeout(
        "laniusc JSON source-pack manifest conflict diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "conflicting source-pack manifest options should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "conflicting source-pack manifest options should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0032");
    assert_eq!(diagnostic["title"], "incompatible CLI options");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "incompatible CLI options");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("incompatible options diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--source-pack-manifest")),
        "diagnostic notes should identify the source-pack manifest option\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--source-pack-library-manifest")),
        "diagnostic notes should identify the source-pack library manifest option\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("choose either")),
        "diagnostic notes should include a remediation hint\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_source_pack_mode_conflicts_can_render_json_without_loading_inputs() {
    for (label, args, option, incompatible, remediation) in [
        (
            "descriptor legacy",
            vec![
                "--diagnostic-format=json",
                "--source-pack-descriptors",
                "--source-pack-legacy-in-memory",
            ],
            "--source-pack-descriptors",
            "--source-pack-legacy-in-memory",
            "choose descriptor mode",
        ),
        (
            "emit contract legacy",
            vec![
                "--diagnostic-format=json",
                "--emit-contract",
                "--source-pack-legacy-in-memory",
            ],
            "--emit-contract",
            "--source-pack-legacy-in-memory",
            "only applies to source-pack descriptor mode",
        ),
        (
            "metadata build-from-metadata",
            vec![
                "--diagnostic-format=json",
                "--source-pack-metadata-only",
                "--source-pack-build-from-metadata",
            ],
            "--source-pack-metadata-only",
            "--source-pack-build-from-metadata",
            "choose either metadata preparation",
        ),
        (
            "metadata legacy",
            vec![
                "--diagnostic-format=json",
                "--source-pack-metadata-only",
                "--source-pack-legacy-in-memory",
            ],
            "--source-pack-metadata-only",
            "--source-pack-legacy-in-memory",
            "requires descriptor mode",
        ),
        (
            "metadata prepare",
            vec![
                "--diagnostic-format=json",
                "--source-pack-prepare-only",
                "--source-pack-metadata-only",
            ],
            "--source-pack-prepare-only",
            "--source-pack-metadata-only",
            "choose one bounded preparation stage",
        ),
        (
            "prepare legacy",
            vec![
                "--diagnostic-format=json",
                "--source-pack-prepare-only",
                "--source-pack-legacy-in-memory",
            ],
            "--source-pack-prepare-only",
            "--source-pack-legacy-in-memory",
            "requires descriptor mode",
        ),
        (
            "prepare stage",
            vec![
                "--diagnostic-format=json",
                "--source-pack-prepare-only",
                "--source-pack-build-prepare-only",
            ],
            "--source-pack-prepare-only",
            "--source-pack-build-prepare-only",
            "choose one bounded preparation stage",
        ),
        (
            "prepare persisted metadata",
            vec![
                "--diagnostic-format=json",
                "--source-pack-prepare-only",
                "--source-pack-build-from-metadata",
            ],
            "--source-pack-prepare-only",
            "--source-pack-build-from-metadata",
            "use --source-pack-build-from-metadata --source-pack-build-prepare-only",
        ),
        (
            "build-from-metadata legacy",
            vec![
                "--diagnostic-format=json",
                "--source-pack-build-from-metadata",
                "--source-pack-legacy-in-memory",
            ],
            "--source-pack-build-from-metadata",
            "--source-pack-legacy-in-memory",
            "requires descriptor mode",
        ),
        (
            "metadata output",
            vec![
                "--diagnostic-format=json",
                "--source-pack-metadata-only",
                "-o",
                "unused.wasm",
            ],
            "--source-pack-metadata-only",
            "-o/--out",
            "no target bytes are emitted",
        ),
        (
            "prepare output",
            vec![
                "--diagnostic-format=json",
                "--source-pack-prepare-only",
                "-o",
                "unused.wasm",
            ],
            "--source-pack-prepare-only",
            "-o/--out",
            "no target bytes are emitted",
        ),
        (
            "build-prepare output",
            vec![
                "--diagnostic-format=json",
                "--source-pack-build-from-metadata",
                "--source-pack-build-prepare-only",
                "-o",
                "unused.wasm",
            ],
            "--source-pack-build-prepare-only",
            "-o/--out",
            "no target bytes are emitted",
        ),
        (
            "build-prepare missing metadata mode",
            vec![
                "--diagnostic-format=json",
                "--source-pack-build-prepare-only",
            ],
            "--source-pack-build-prepare-only",
            "metadata-free source-pack compilation",
            "add --source-pack-build-from-metadata",
        ),
    ] {
        let mut command = Command::new(laniusc_bin());
        command.args(args);
        let output = command_output_with_timeout(
            &format!("laniusc JSON source-pack {label} conflict diagnostic"),
            &mut command,
            CLI_DIAGNOSTIC_TIMEOUT,
        )
        .expect("spawn laniusc");

        assert!(
            !output.status.success(),
            "conflicting source-pack mode options should fail\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            output.stdout.is_empty(),
            "conflicting source-pack mode options should not write stdout bytes\nstdout bytes: {}",
            output.stdout.len()
        );

        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(
            !stderr.contains("laniusc:"),
            "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
        );
        let diagnostic: serde_json::Value =
            serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
        assert_eq!(diagnostic["severity"], "error");
        assert_eq!(diagnostic["code"], "LNC0032");
        assert_eq!(diagnostic["title"], "incompatible CLI options");
        assert_eq!(diagnostic["category"], "tooling");
        assert_eq!(diagnostic["message"], "incompatible CLI options");
        assert!(diagnostic["primary_label"].is_null());
        let notes = diagnostic["notes"]
            .as_array()
            .expect("incompatible options diagnostic should include notes");
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(option)),
            "diagnostic notes should identify the first incompatible option\nstderr:\n{stderr}"
        );
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(incompatible)),
            "diagnostic notes should identify the second incompatible option\nstderr:\n{stderr}"
        );
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(remediation)),
            "diagnostic notes should include a mode-selection remediation\nstderr:\n{stderr}"
        );
    }
}

#[test]
fn cli_source_pack_descriptor_output_mode_can_render_json_without_loading_inputs() {
    let root = common::temp_artifact_path(
        "laniusc_cli_diagnostics",
        "source_pack_descriptor_output_mode_json",
        None,
    );
    let artifact_root = root.join("artifacts");
    let output_path = root.join("out");
    let missing_source = root.join("missing.lani");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=json")
        .arg("--emit=x86_64")
        .arg("--source-pack-descriptors")
        .arg("--source-pack-artifact-root")
        .arg(&artifact_root)
        .arg("-o")
        .arg(&output_path)
        .arg(&missing_source);
    let output = command_output_with_timeout(
        "laniusc JSON source-pack descriptor output-mode diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");
    let _ = fs::remove_dir_all(&root);

    assert!(
        !output.status.success(),
        "implicit descriptor target-byte output should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "descriptor output-mode validation should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );
    assert!(
        !output_path.exists(),
        "descriptor output-mode validation must not leave output artifacts"
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("missing.lani"),
        "descriptor output-mode validation should happen before source loading\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0032");
    assert_eq!(diagnostic["title"], "incompatible CLI options");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "incompatible CLI options");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("descriptor output-mode diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("source-pack descriptor mode")),
        "diagnostic notes should identify descriptor mode\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--emit-contract")),
        "diagnostic notes should describe the contract-output remediation\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--source-pack-legacy-in-memory")),
        "diagnostic notes should describe the target-byte remediation\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_missing_public_selector_values_can_render_json_diagnostics_without_compiling_source() {
    for (label, option, expected_value, args) in [
        (
            "edition",
            "--edition",
            "unstable-alpha",
            vec!["--diagnostic-format=json", "--edition"],
        ),
        (
            "target",
            "--target",
            "wasm32-unknown-unknown",
            vec!["--diagnostic-format=json", "--target"],
        ),
        (
            "diagnostic-format",
            "--diagnostic-format",
            "text, json, lsp-json",
            vec!["--diagnostic-format=json", "--diagnostic-format"],
        ),
    ] {
        let mut command = Command::new(laniusc_bin());
        command.args(args);
        let output = command_output_with_timeout(
            &format!("laniusc JSON missing {label} value diagnostic"),
            &mut command,
            CLI_DIAGNOSTIC_TIMEOUT,
        )
        .expect("spawn laniusc");

        assert!(
            !output.status.success(),
            "missing {label} value should fail\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            output.stdout.is_empty(),
            "missing {label} value should not write stdout bytes\nstdout bytes: {}",
            output.stdout.len()
        );

        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(
            !stderr.contains("laniusc:"),
            "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
        );
        let diagnostic: serde_json::Value =
            serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
        assert_eq!(diagnostic["severity"], "error");
        assert_eq!(diagnostic["code"], "LNC0023");
        assert_eq!(diagnostic["title"], "missing CLI option value");
        assert_eq!(diagnostic["category"], "tooling");
        assert_eq!(diagnostic["message"], "missing CLI option value");
        assert!(diagnostic["primary_label"].is_null());
        let notes = diagnostic["notes"]
            .as_array()
            .expect("missing value diagnostic should include notes");
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(option)),
            "diagnostic notes should identify the option\nstderr:\n{stderr}"
        );
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(expected_value)),
            "diagnostic notes should list accepted values\nstderr:\n{stderr}"
        );
    }
}

#[test]
fn cli_missing_public_path_values_can_render_json_diagnostics_without_loading_inputs() {
    for (label, option, expected_value, args) in [
        (
            "stdlib",
            "--stdlib",
            "a source file path",
            vec!["--diagnostic-format=json", "--stdlib"],
        ),
        (
            "stdlib-root",
            "--stdlib-root",
            "a directory path",
            vec!["--diagnostic-format=json", "--stdlib-root"],
        ),
        (
            "source-root",
            "--source-root",
            "a directory path",
            vec!["--diagnostic-format=json", "--source-root"],
        ),
        (
            "package-manifest",
            "--package-manifest",
            "a path",
            vec!["--diagnostic-format=json", "--package-manifest"],
        ),
        (
            "package-lockfile",
            "--package-lockfile",
            "a path",
            vec!["--diagnostic-format=json", "--package-lockfile"],
        ),
        (
            "output",
            "-o",
            "an output path",
            vec!["--diagnostic-format=json", "-o"],
        ),
        (
            "source-pack-manifest",
            "--source-pack-manifest",
            "a path",
            vec!["--diagnostic-format=json", "--source-pack-manifest"],
        ),
        (
            "source-pack-library-manifest",
            "--source-pack-library-manifest",
            "a path",
            vec!["--diagnostic-format=json", "--source-pack-library-manifest"],
        ),
        (
            "source-pack-artifact-root",
            "--source-pack-artifact-root",
            "a path",
            vec!["--diagnostic-format=json", "--source-pack-artifact-root"],
        ),
    ] {
        let mut command = Command::new(laniusc_bin());
        command.args(args);
        let output = command_output_with_timeout(
            &format!("laniusc JSON missing {label} path diagnostic"),
            &mut command,
            CLI_DIAGNOSTIC_TIMEOUT,
        )
        .expect("spawn laniusc");

        assert!(
            !output.status.success(),
            "missing {label} path should fail\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            output.stdout.is_empty(),
            "missing {label} path should not write stdout bytes\nstdout bytes: {}",
            output.stdout.len()
        );

        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(
            !stderr.contains("laniusc:"),
            "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
        );
        let diagnostic: serde_json::Value =
            serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
        assert_eq!(diagnostic["severity"], "error");
        assert_eq!(diagnostic["code"], "LNC0023");
        assert_eq!(diagnostic["title"], "missing CLI option value");
        assert_eq!(diagnostic["category"], "tooling");
        assert_eq!(diagnostic["message"], "missing CLI option value");
        assert!(diagnostic["primary_label"].is_null());
        let notes = diagnostic["notes"]
            .as_array()
            .expect("missing value diagnostic should include notes");
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(option)),
            "diagnostic notes should identify the option\nstderr:\n{stderr}"
        );
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(expected_value)),
            "diagnostic notes should describe the required value\nstderr:\n{stderr}"
        );
    }
}

#[test]
fn cli_missing_public_limit_values_can_render_json_diagnostics_without_loading_inputs() {
    for (label, option, args) in [
        (
            "metadata max libraries",
            "--source-pack-metadata-max-libraries",
            vec![
                "--diagnostic-format=json",
                "--source-pack-metadata-max-libraries",
            ],
        ),
        (
            "metadata max source files",
            "--source-pack-metadata-max-source-files",
            vec![
                "--diagnostic-format=json",
                "--source-pack-metadata-max-source-files",
            ],
        ),
        (
            "build max items",
            "--source-pack-build-max-items",
            vec!["--diagnostic-format=json", "--source-pack-build-max-items"],
        ),
        (
            "max items",
            "--source-pack-max-items",
            vec!["--diagnostic-format=json", "--source-pack-max-items"],
        ),
        (
            "max ready items",
            "--source-pack-max-ready-items",
            vec!["--diagnostic-format=json", "--source-pack-max-ready-items"],
        ),
    ] {
        let mut command = Command::new(laniusc_bin());
        command.args(args);
        let output = command_output_with_timeout(
            &format!("laniusc JSON missing {label} limit diagnostic"),
            &mut command,
            CLI_DIAGNOSTIC_TIMEOUT,
        )
        .expect("spawn laniusc");

        assert!(
            !output.status.success(),
            "missing {label} limit should fail\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            output.stdout.is_empty(),
            "missing {label} limit should not write stdout bytes\nstdout bytes: {}",
            output.stdout.len()
        );

        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(
            !stderr.contains("laniusc:"),
            "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
        );
        let diagnostic: serde_json::Value =
            serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
        assert_eq!(diagnostic["severity"], "error");
        assert_eq!(diagnostic["code"], "LNC0023");
        assert_eq!(diagnostic["title"], "missing CLI option value");
        assert_eq!(diagnostic["category"], "tooling");
        assert_eq!(diagnostic["message"], "missing CLI option value");
        assert!(diagnostic["primary_label"].is_null());
        let notes = diagnostic["notes"]
            .as_array()
            .expect("missing value diagnostic should include notes");
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(option)),
            "diagnostic notes should identify the option\nstderr:\n{stderr}"
        );
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains("a non-negative integer")),
            "diagnostic notes should describe the required integer\nstderr:\n{stderr}"
        );
    }
}

#[test]
fn cli_invalid_public_limit_values_can_render_json_diagnostics_without_loading_inputs() {
    for (label, option, args) in [
        (
            "metadata max libraries",
            "--source-pack-metadata-max-libraries",
            vec![
                "--diagnostic-format=json",
                "--source-pack-metadata-max-libraries",
                "not-a-number",
            ],
        ),
        (
            "max ready items",
            "--source-pack-max-ready-items",
            vec![
                "--diagnostic-format=json",
                "--source-pack-max-ready-items=not-a-number",
            ],
        ),
    ] {
        let mut command = Command::new(laniusc_bin());
        command.args(args).arg("/definitely/not/a/source/file.lani");
        let output = command_output_with_timeout(
            &format!("laniusc JSON invalid {label} limit diagnostic"),
            &mut command,
            CLI_DIAGNOSTIC_TIMEOUT,
        )
        .expect("spawn laniusc");

        assert!(
            !output.status.success(),
            "invalid {label} limit should fail\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            output.stdout.is_empty(),
            "invalid {label} limit should not write stdout bytes\nstdout bytes: {}",
            output.stdout.len()
        );

        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(
            !stderr.contains("laniusc:"),
            "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
        );
        assert!(
            !stderr.contains("/definitely/not/a/source/file.lani"),
            "limit validation should happen before source loading\nstderr:\n{stderr}"
        );
        let diagnostic: serde_json::Value =
            serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
        assert_eq!(diagnostic["severity"], "error");
        assert_eq!(diagnostic["code"], "LNC0018");
        assert_eq!(diagnostic["title"], "unsupported CLI option value");
        assert_eq!(diagnostic["category"], "tooling");
        assert_eq!(diagnostic["message"], "unsupported CLI option value");
        assert!(diagnostic["primary_label"].is_null());
        let notes = diagnostic["notes"]
            .as_array()
            .expect("invalid value diagnostic should include notes");
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(option)),
            "diagnostic notes should identify the option\nstderr:\n{stderr}"
        );
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains("not-a-number")),
            "diagnostic notes should include the rejected value\nstderr:\n{stderr}"
        );
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains("non-negative integer")),
            "diagnostic notes should describe the accepted value class\nstderr:\n{stderr}"
        );
    }
}

#[test]
fn cli_package_lock_missing_option_values_can_render_json_diagnostics_without_loading_manifest() {
    for (label, option, expected_value, args) in [
        (
            "manifest",
            "--manifest",
            "a path",
            vec!["package", "lock", "--diagnostic-format=json", "--manifest"],
        ),
        (
            "output",
            "-o",
            "an output path",
            vec!["package", "lock", "--diagnostic-format=json", "-o"],
        ),
    ] {
        let mut command = Command::new(laniusc_bin());
        command.args(args);
        let output = command_output_with_timeout(
            &format!("laniusc package lock JSON missing {label} value diagnostic"),
            &mut command,
            CLI_DIAGNOSTIC_TIMEOUT,
        )
        .expect("spawn laniusc package lock");

        assert!(
            !output.status.success(),
            "missing package lock {label} value should fail\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            output.stdout.is_empty(),
            "missing package lock {label} value should not write stdout bytes\nstdout bytes: {}",
            output.stdout.len()
        );

        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(
            !stderr.contains("laniusc:"),
            "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
        );
        let diagnostic: serde_json::Value =
            serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
        assert_eq!(diagnostic["severity"], "error");
        assert_eq!(diagnostic["code"], "LNC0023");
        assert_eq!(diagnostic["title"], "missing CLI option value");
        assert_eq!(diagnostic["category"], "tooling");
        assert_eq!(diagnostic["message"], "missing CLI option value");
        assert!(diagnostic["primary_label"].is_null());
        let notes = diagnostic["notes"]
            .as_array()
            .expect("missing value diagnostic should include notes");
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(option)),
            "diagnostic notes should identify the option\nstderr:\n{stderr}"
        );
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(expected_value)),
            "diagnostic notes should describe the required value\nstderr:\n{stderr}"
        );
    }
}

#[test]
fn cli_package_lock_missing_selectors_emit_json_diagnostics_without_loading_manifest() {
    for (label, args, expected_argument) in [
        (
            "manifest selector",
            vec![
                "package",
                "lock",
                "--diagnostic-format=json",
                "-o",
                "/tmp/laniusc-package-lock-missing-manifest-output.json",
            ],
            "--manifest path",
        ),
        (
            "output selector",
            vec![
                "package",
                "lock",
                "--diagnostic-format=json",
                "--manifest",
                "/tmp/laniusc-package-lock-missing-output-manifest.json",
            ],
            "-o/--out path",
        ),
    ] {
        let mut command = Command::new(laniusc_bin());
        command.args(args);
        let output = command_output_with_timeout(
            &format!("laniusc package lock JSON missing required {label} diagnostic"),
            &mut command,
            CLI_DIAGNOSTIC_TIMEOUT,
        )
        .expect("spawn laniusc package lock");

        assert!(
            !output.status.success(),
            "missing package lock {label} should fail\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            output.stdout.is_empty(),
            "missing package lock {label} should not write stdout bytes\nstdout bytes: {}",
            output.stdout.len()
        );

        let stderr = String::from_utf8_lossy(&output.stderr);
        assert!(
            !stderr.contains("laniusc:"),
            "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
        );
        let diagnostic: serde_json::Value =
            serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
        assert_eq!(diagnostic["severity"], "error");
        assert_eq!(diagnostic["code"], "LNC0026");
        assert_eq!(diagnostic["title"], "missing CLI argument");
        assert_eq!(diagnostic["category"], "tooling");
        assert_eq!(diagnostic["message"], "missing CLI argument");
        assert!(diagnostic["primary_label"].is_null());
        let notes = diagnostic["notes"]
            .as_array()
            .expect("missing argument diagnostic should include notes");
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains("laniusc package lock requires")),
            "diagnostic notes should identify the package lock command\nstderr:\n{stderr}"
        );
        assert!(
            notes.iter().any(|note| note
                .as_str()
                .expect("diagnostic note should be a string")
                .contains(expected_argument)),
            "diagnostic notes should describe the missing selector\nstderr:\n{stderr}"
        );
    }
}

#[test]
fn cli_package_lock_manifest_overwrite_can_render_json_incompatible_options_diagnostic() {
    let root = common::temp_artifact_path("laniusc_cli_diagnostics", "package_lock", None);
    let app_root = root.join("src/app");
    fs::create_dir_all(&app_root).expect("create package source root");
    fs::write(
        app_root.join("main.lani"),
        "module app::main;\n\nfn main() {\n    return 0;\n}\n",
    )
    .expect("write package entry source");
    let manifest = root.join("lanius.package.json");
    fs::write(
        &manifest,
        r#"{
  "package": "diagnostic-package",
  "roots": ["src"],
  "entry": "src/app/main.lani"
}"#,
    )
    .expect("write package manifest");
    let original_manifest =
        fs::read_to_string(&manifest).expect("read package manifest before command");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("package")
        .arg("lock")
        .arg("--diagnostic-format=json")
        .arg("--manifest")
        .arg(&manifest)
        .arg("-o")
        .arg(&manifest);
    let output = command_output_with_timeout(
        "laniusc package lock JSON manifest overwrite diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc package lock");

    assert!(
        !output.status.success(),
        "manifest overwrite should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "manifest overwrite diagnostic should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );
    assert_eq!(
        fs::read_to_string(&manifest).expect("read package manifest after command"),
        original_manifest,
        "failed package lock command must not overwrite the package manifest"
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0032");
    assert_eq!(diagnostic["title"], "incompatible CLI options");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "incompatible CLI options");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("incompatible options diagnostic should include notes");
    assert!(
        notes.iter().any(|note| {
            let note = note.as_str().expect("diagnostic note should be a string");
            note.contains("laniusc package lock")
                && note.contains("-o/--out")
                && note.contains("--manifest path")
        }),
        "diagnostic notes should identify the conflicting selectors\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| {
            let note = note.as_str().expect("diagnostic note should be a string");
            note.contains("would overwrite package manifest")
                && note.contains(&manifest.display().to_string())
        }),
        "diagnostic notes should describe the overwrite boundary\nstderr:\n{stderr}"
    );

    fs::remove_dir_all(&root).expect("remove package lock diagnostics fixture");
}

#[test]
fn cli_package_missing_subcommand_can_render_json_diagnostic() {
    let mut command = Command::new(laniusc_bin());
    command.args(["package", "--diagnostic-format=json"]);
    let output = command_output_with_timeout(
        "laniusc package JSON missing subcommand diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc package");

    assert!(
        !output.status.success(),
        "missing package subcommand should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "missing package subcommand should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0025");
    assert_eq!(diagnostic["title"], "missing CLI subcommand");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "missing CLI subcommand");
    assert!(diagnostic["primary_label"].is_null());
    assert!(
        diagnostic["help"]
            .as_str()
            .is_some_and(|help| help.contains("laniusc package --help")),
        "missing package subcommand should expose public recovery help\nstderr:\n{stderr}"
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("missing package subcommand diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc package")),
        "diagnostic notes should identify the package command\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("lock")),
        "diagnostic notes should list accepted package subcommands\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_package_unknown_subcommand_can_render_json_diagnostic_without_loading_manifest() {
    let mut command = Command::new(laniusc_bin());
    command.args(["package", "publish", "--diagnostic-format=json"]);
    let output = command_output_with_timeout(
        "laniusc package JSON unknown subcommand diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc package");

    assert!(
        !output.status.success(),
        "unknown package subcommand should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "unknown package subcommand should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0039");
    assert_eq!(diagnostic["title"], "unknown CLI subcommand");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unknown CLI subcommand");
    assert!(diagnostic["primary_label"].is_null());
    assert!(
        diagnostic["help"]
            .as_str()
            .is_some_and(|help| help.contains("laniusc package --help")),
        "unknown package subcommand should expose public recovery help\nstderr:\n{stderr}"
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("unknown package subcommand diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc package")),
        "diagnostic notes should identify the package command\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("publish")),
        "diagnostic notes should identify the rejected subcommand\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("lock")),
        "diagnostic notes should list accepted package subcommands\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_package_lock_positional_argument_can_render_json_diagnostic_without_loading_manifest() {
    let mut command = Command::new(laniusc_bin());
    command.args([
        "package",
        "lock",
        "--diagnostic-format=json",
        "src/app/main.lani",
    ]);
    let output = command_output_with_timeout(
        "laniusc package lock JSON unexpected positional diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc package lock");

    assert!(
        !output.status.success(),
        "unexpected package lock positional argument should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "unexpected package lock positional argument should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0031");
    assert_eq!(diagnostic["title"], "unexpected CLI argument");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unexpected CLI argument");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("unexpected package lock argument diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc package lock")),
        "diagnostic notes should identify the package lock command\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("src/app/main.lani")),
        "diagnostic notes should identify the rejected positional path\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--manifest")),
        "diagnostic notes should list accepted package lock selectors\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_unsupported_edition_can_render_lsp_json_diagnostic_before_source_loading() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=lsp-json")
        .arg("--edition=future-stable")
        .arg("/definitely/not/a/source/file.lani");
    let output = command_output_with_timeout(
        "laniusc LSP JSON unsupported edition diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "unsupported edition should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "unsupported edition should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "LSP JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("/definitely/not/a/source/file.lani"),
        "edition validation should happen before source loading\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one LSP diagnostic object");
    assert_eq!(diagnostic["severity"], 1);
    assert_eq!(diagnostic["code"], "LNC0018");
    assert_eq!(diagnostic["source"], "laniusc");
    assert_eq!(diagnostic["message"], "unsupported CLI option value");
    assert_eq!(
        diagnostic["data"]["schema_version"],
        laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["data"]["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(diagnostic["data"]["position_encoding"], "utf-16");
    assert_eq!(diagnostic["data"]["title"], "unsupported CLI option value");
    assert_eq!(diagnostic["data"]["category"], "tooling");
    assert_eq!(diagnostic["data"]["primary_label_policy"], "none");
    assert_eq!(
        diagnostic["data"]["explain_command"],
        "laniusc diagnostics explain LNC0018"
    );
    let notes = diagnostic["data"]["notes"]
        .as_array()
        .expect("LSP diagnostic data should carry option notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--edition")),
        "LSP diagnostic data notes should identify the option\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("unstable-alpha")),
        "LSP diagnostic data notes should list the accepted edition\nstderr:\n{stderr}"
    );
    assert!(diagnostic["data"].get("primary_label").is_none());
    assert_eq!(diagnostic["range"]["start"]["line"], 0);
    assert_eq!(diagnostic["range"]["start"]["character"], 0);
    assert_eq!(diagnostic["range"]["end"]["line"], 0);
    assert_eq!(diagnostic["range"]["end"]["character"], 0);
    assert!(diagnostic.get("primary_label").is_none());
    assert!(diagnostic.get("notes").is_none());
    assert!(diagnostic.get("diagnostics").is_none());
}

#[test]
fn cli_unknown_flag_can_render_json_diagnostic_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=json")
        .arg("--not-a-real-flag")
        .arg("/definitely/not/a/source/file.lani");
    let output = command_output_with_timeout(
        "laniusc JSON unknown flag diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "unknown flag should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "unknown flag should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("/definitely/not/a/source/file.lani"),
        "unknown flag validation should happen before source loading\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0020");
    assert_eq!(diagnostic["title"], "unknown CLI option");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unknown CLI option");
    assert!(diagnostic["primary_label"].is_null());
    assert!(
        diagnostic["help"]
            .as_str()
            .is_some_and(|help| help.contains("use an accepted option")),
        "unknown option diagnostics should expose public recovery help\nstderr:\n{stderr}"
    );
    let notes = diagnostic["notes"]
        .as_array()
        .expect("unknown flag diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--not-a-real-flag")),
        "diagnostic notes should identify the unknown flag\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("--diagnostic-format")),
        "diagnostic notes should list accepted CLI options\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_diagnostics_categories_lsp_json_selector_still_prints_metadata_document() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("--diagnostic-format=lsp-json")
        .arg("categories");
    let output = command_output_with_timeout(
        "laniusc diagnostics categories with lsp-json selector",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics categories");

    assert!(
        output.status.success(),
        "diagnostics categories should accept the LSP diagnostic renderer selector\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "successful no-run metadata queries should not render LSP diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("categories output should be JSON metadata");
    assert_eq!(document["schema_version"], 4);
    assert_eq!(document["schema_name"], "laniusc.diagnostics.categories");
    assert_eq!(
        document["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["source_scanning"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    let categories = document["categories"]
        .as_array()
        .expect("categories should be an array");
    assert_eq!(document["category_count"], categories.len());
    assert!(
        categories
            .iter()
            .any(|category| category["name"] == "tooling"),
        "categories metadata should still expose the tooling group"
    );
    assert!(
        document.get("source").is_none(),
        "successful metadata output should not be an LSP Diagnostic object"
    );
}

#[test]
fn cli_diagnostics_registry_accepts_diagnostic_format_after_subcommand() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("registry")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics registry with trailing diagnostic format",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics registry");

    assert!(
        output.status.success(),
        "diagnostics registry should accept global diagnostic format after subcommand\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics registry should not print a diagnostic\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let registry: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("registry output should be JSON");
    assert_eq!(
        registry["schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert!(
        registry["codes"]
            .as_array()
            .expect("registry codes should be an array")
            .iter()
            .any(|code| code["code"] == "LNC0017"),
        "registry should still print diagnostic code metadata"
    );
}

#[test]
fn cli_diagnostics_formats_accepts_diagnostic_format_after_subcommand() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("formats")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics formats with trailing diagnostic format",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics formats");

    assert!(
        output.status.success(),
        "diagnostics formats should accept global diagnostic format after subcommand\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics formats should not print a diagnostic\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let formats: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("formats output should be JSON");
    assert_eq!(
        formats["schema_version"],
        laniusc::compiler::DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_VERSION
    );
    assert_eq!(
        formats["schema_name"],
        laniusc::compiler::DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_NAME
    );
    assert_eq!(formats["cli_flag"], "--diagnostic-format");
    assert_eq!(formats["default_format"], "text");
    assert_eq!(
        formats["accepted_formats"]
            .as_array()
            .expect("accepted diagnostic formats should be an array")
            .iter()
            .map(|format| format
                .as_str()
                .expect("accepted diagnostic format should be a string"))
            .collect::<Vec<_>>(),
        vec!["text", "json", "lsp-json"]
    );
    assert_eq!(formats["no_run_guards"]["source_compilation"], false);
    assert_eq!(formats["no_run_guards"]["source_scanning"], false);
    assert_eq!(formats["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(formats["no_run_guards"]["target_codegen"], false);
    assert!(
        formats["formats"]
            .as_array()
            .expect("format rows should be an array")
            .iter()
            .any(|format| format["name"] == "lsp-json"),
        "format registry should still describe lsp-json"
    );
}

#[test]
fn cli_diagnostics_explain_accepts_diagnostic_format_after_code() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("explain")
        .arg("LNC0017")
        .arg("--diagnostic-format=json");
    let output = command_output_with_timeout(
        "laniusc diagnostics explain with trailing diagnostic format",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics explain");

    assert!(
        output.status.success(),
        "diagnostics explain should accept global diagnostic format after code\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stderr.is_empty(),
        "diagnostics explain should not print a diagnostic\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let explanation: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("explanation output should be JSON");
    assert_eq!(
        explanation["schema_version"],
        laniusc::compiler::DIAGNOSTIC_EXPLANATION_SCHEMA_VERSION
    );
    assert_eq!(explanation["requested_code"], "LNC0017");
    assert_eq!(
        explanation["explain_command"],
        "laniusc diagnostics explain LNC0017"
    );
    assert_eq!(explanation["known"], true);
    assert_eq!(explanation["diagnostic"]["code"], "LNC0017");
}

#[test]
fn cli_no_run_diagnostic_help_advertises_machine_readable_invocation_diagnostics() {
    for (context, args, expected_usages) in [
        (
            "laniusc --help",
            &["--help"][..],
            &[
                "Usage: laniusc package lock [--diagnostic-format text|json|lsp-json] --manifest path -o path",
                "Usage: laniusc lsp [--diagnostic-format text|json|lsp-json] capabilities",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] registry",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] codes",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-api API",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-apis",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-service SERVICE",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-service-apis SERVICE",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-services",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] source-pack-progress --source-pack-artifact-root dir [--emit wasm|x86_64]",
                "Usage: laniusc doctor [--diagnostic-format text|json|lsp-json]",
            ][..],
        ),
        (
            "laniusc diagnostics --help",
            &["diagnostics", "--help"][..],
            &[
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] registry",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] codes",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] explain CODE",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-api API",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-apis",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-service SERVICE",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-service-apis SERVICE",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] runtime-services",
            ][..],
        ),
        (
            "laniusc package --help",
            &["package", "--help"][..],
            &[
                "Usage: laniusc package lock [--diagnostic-format text|json|lsp-json] --manifest path -o path",
            ][..],
        ),
        (
            "laniusc package lock --help",
            &["package", "lock", "--help"][..],
            &[
                "Usage: laniusc package lock [--diagnostic-format text|json|lsp-json] --manifest path -o path",
            ][..],
        ),
        (
            "laniusc lsp --help",
            &["lsp", "--help"][..],
            &[
                "Usage: laniusc lsp [--diagnostic-format text|json|lsp-json] capabilities",
                "Usage: laniusc lsp [--diagnostic-format text|json|lsp-json] serve --stdio",
            ][..],
        ),
    ] {
        let mut command = Command::new(laniusc_bin());
        command.args(args);
        let output = command_output_with_timeout(context, &mut command, CLI_DIAGNOSTIC_TIMEOUT)
            .unwrap_or_else(|err| panic!("spawn {context}: {err}"));

        assert!(
            output.status.success(),
            "{context} should succeed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
        assert!(
            output.stdout.is_empty(),
            "{context} help should be written to stderr\nstdout:\n{}",
            String::from_utf8_lossy(&output.stdout)
        );
        let stderr = String::from_utf8_lossy(&output.stderr);
        for usage in expected_usages {
            assert!(
                stderr.contains(usage),
                "{context} should advertise diagnostic-format support in usage\nstderr:\n{stderr}"
            );
        }
        assert!(
            stderr
                .contains("--diagnostic-format selects text, JSON, or LSP Diagnostic-shaped JSON"),
            "{context} should describe machine-readable invocation diagnostics\nstderr:\n{stderr}"
        );
    }
}

#[test]
fn cli_lsp_malformed_diagnostic_format_flag_lists_lsp_commands() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("lsp")
        .arg("--diagnostic-format=json")
        .arg("--diagnostic-formatty")
        .arg("capabilities");
    let output = command_output_with_timeout(
        "laniusc lsp malformed diagnostic-format flag",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc lsp");

    assert!(
        !output.status.success(),
        "malformed lsp diagnostic-format flag should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "malformed lsp diagnostic-format flag should not print capabilities\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0020");
    assert_eq!(diagnostic["title"], "unknown CLI option");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unknown CLI option");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("malformed flag diagnostic should include notes");
    assert!(notes.iter().any(|note| {
        let note = note.as_str().expect("diagnostic note should be a string");
        note.contains("laniusc lsp") && note.contains("--diagnostic-formatty")
    }));
    assert!(notes.iter().any(|note| {
        let note = note.as_str().expect("diagnostic note should be a string");
        note.contains("capabilities") && !note.contains("registry")
    }));
}

#[test]
fn cli_linked_output_contract_descriptor_rejects_target_bytes_as_json_diagnostic() {
    let root = common::temp_artifact_path(
        "laniusc_cli_diagnostics",
        "linked_output_contract_target_bytes_json",
        None,
    );
    let artifact_root = root.join("artifacts");
    let linked_output_key = "wasm/linked-output/job-0/src-0-1";
    let linked_output = seed_completed_descriptor_root(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        linked_output_key,
    );
    fs::write(&linked_output, b"\0asmnot-a-contract").expect("write fake wasm linked output");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=json")
        .arg("--emit=wasm")
        .arg("--source-pack-build-from-metadata")
        .arg("--source-pack-artifact-root")
        .arg(&artifact_root)
        .arg("--emit-contract");
    let output = command_output_with_timeout(
        "laniusc JSON linked-output contract descriptor diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");
    fs::remove_dir_all(&root).expect("remove temp descriptor root");

    assert!(
        !output.status.success(),
        "invalid linked-output contract should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "invalid linked-output contract should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0022");
    assert_eq!(diagnostic["title"], "linked-output contract descriptor");
    assert_eq!(diagnostic["category"], "native codegen");
    assert_eq!(diagnostic["message"], "linked-output contract descriptor");
    assert_eq!(
        diagnostic["primary_label"]["path"],
        linked_output.display().to_string()
    );
    assert_eq!(diagnostic["primary_label"]["line"], 1);
    assert_eq!(diagnostic["primary_label"]["column"], 1);
    assert_eq!(diagnostic["primary_label"]["length"], 1);
    assert!(diagnostic["primary_label"]["source_line"].is_null());
    assert!(
        !diagnostic["notes"]
            .as_array()
            .expect("descriptor diagnostic should include notes")
            .is_empty()
    );
}

#[test]
fn cli_linked_output_contract_descriptor_rejects_target_bytes_as_lsp_json_diagnostic() {
    let root = common::temp_artifact_path(
        "laniusc_cli_diagnostics",
        "linked_output_contract_target_bytes_lsp_json",
        None,
    );
    let artifact_root = root.join("artifacts");
    let linked_output_key = "wasm/linked-output/job-0/src-0-1";
    let linked_output = seed_completed_descriptor_root(
        &artifact_root,
        SourcePackArtifactTarget::Wasm,
        linked_output_key,
    );
    fs::write(&linked_output, b"\0asmnot-a-contract").expect("write fake wasm linked output");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=lsp-json")
        .arg("--emit=wasm")
        .arg("--source-pack-build-from-metadata")
        .arg("--source-pack-artifact-root")
        .arg(&artifact_root)
        .arg("--emit-contract");
    let output = command_output_with_timeout(
        "laniusc LSP JSON linked-output contract descriptor diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");
    fs::remove_dir_all(&root).expect("remove temp descriptor root");

    assert!(
        !output.status.success(),
        "invalid linked-output contract should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "invalid linked-output contract should not write stdout bytes\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "LSP JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one LSP diagnostic object");
    assert_eq!(diagnostic["severity"], 1);
    assert_eq!(diagnostic["code"], "LNC0022");
    assert_eq!(diagnostic["source"], "laniusc");
    assert_eq!(diagnostic["message"], "linked-output contract descriptor");
    assert_eq!(
        diagnostic["data"]["schema_version"],
        laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["data"]["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["data"]["title"],
        "linked-output contract descriptor"
    );
    assert_eq!(diagnostic["data"]["category"], "native codegen");
    assert_eq!(diagnostic["data"]["primary_label_policy"], "required");
    let notes = diagnostic["data"]["notes"]
        .as_array()
        .expect("LSP diagnostic data should carry descriptor notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("target bytes")),
        "LSP diagnostic data notes should explain rejected target bytes\nstderr:\n{stderr}"
    );
    assert_eq!(diagnostic["range"]["start"]["line"], 0);
    assert_eq!(diagnostic["range"]["start"]["character"], 0);
    assert_eq!(diagnostic["range"]["end"]["line"], 0);
    assert_eq!(diagnostic["range"]["end"]["character"], 1);
    assert!(diagnostic.get("category").is_none());
    assert!(diagnostic.get("primary_label").is_none());
    assert!(diagnostic.get("notes").is_none());
    assert!(diagnostic.get("diagnostics").is_none());
}

#[test]
fn diagnostic_lsp_json_renderer_exposes_protocol_fields_without_envelope() {
    let diagnostic = laniusc::compiler::Diagnostic::error("LNC0016", "syntax error")
        .with_primary_label(laniusc::compiler::DiagnosticLabel::primary(
            "app.lani",
            2,
            3,
            2,
            Some("abcdef".to_string()),
            "invalid syntax here",
        ))
        .with_note("parser rejected the token stream");

    let json = diagnostic
        .render_lsp_json_pretty()
        .expect("LSP diagnostic JSON should serialize");
    let value: serde_json::Value =
        serde_json::from_str(&json).expect("LSP diagnostic JSON should parse");

    assert_eq!(value["severity"], 1);
    assert_eq!(value["code"], "LNC0016");
    assert_eq!(value["source"], "laniusc");
    assert_eq!(value["message"], "syntax error");
    assert_eq!(
        value["data"]["schema_version"],
        laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
    );
    assert_eq!(
        value["data"]["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(value["data"]["title"], "syntax error");
    assert_eq!(value["data"]["category"], "parsing");
    assert_eq!(value["data"]["primary_label_policy"], "required");
    assert_eq!(
        value["data"]["explain_command"],
        "laniusc diagnostics explain LNC0016"
    );
    assert_eq!(
        value["data"]["notes"][0],
        "parser rejected the token stream"
    );
    assert_eq!(value["data"]["primary_label"]["path"], "app.lani");
    assert_eq!(value["data"]["primary_label"]["line"], 2);
    assert_eq!(value["data"]["primary_label"]["column"], 3);
    assert_eq!(value["data"]["primary_label"]["length"], 2);
    assert_eq!(
        value["data"]["primary_label"]["message"],
        "invalid syntax here"
    );
    assert_eq!(value["range"]["start"]["line"], 1);
    assert_eq!(value["range"]["start"]["character"], 2);
    assert_eq!(value["range"]["end"]["line"], 1);
    assert_eq!(value["range"]["end"]["character"], 4);
    assert!(value.get("primary_label").is_none());
    assert!(value.get("notes").is_none());
    assert!(value.get("diagnostics").is_none());
}

#[test]
fn diagnostic_lsp_json_renderer_uses_registry_metadata_for_known_codes() {
    let mut diagnostic = laniusc::compiler::Diagnostic::error("LNC0016", "syntax error")
        .with_primary_label(laniusc::compiler::DiagnosticLabel::primary(
            "app.lani",
            1,
            1,
            2,
            Some("fn fn main() {}".to_string()),
            "invalid syntax here",
        ));
    diagnostic.title = "stale caller title".to_string();
    diagnostic.category = "tooling".to_string();

    let lsp_json = diagnostic
        .render_lsp_json_pretty()
        .expect("LSP diagnostic JSON should serialize");
    let value: serde_json::Value =
        serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");

    assert_eq!(value["code"], "LNC0016");
    assert_eq!(value["source"], "laniusc");
    assert_eq!(
        value["data"]["schema_version"],
        laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
    );
    assert_eq!(
        value["data"]["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(value["data"]["title"], "syntax error");
    assert_eq!(value["data"]["category"], "parsing");
    assert_eq!(value["data"]["primary_label_policy"], "required");
    assert_eq!(
        value["data"]["explain_command"],
        "laniusc diagnostics explain LNC0016"
    );
}

#[test]
fn diagnostic_renderers_expose_public_help_metadata_for_unsupported_boundaries() {
    let diagnostic =
        laniusc::compiler::Diagnostic::error("LNC0022", "linked-output contract descriptor")
            .with_primary_label(laniusc::compiler::DiagnosticLabel::primary(
                "linked-output.contract",
                1,
                1,
                1,
                None,
                "linked-output contract descriptor here",
            ))
            .with_note("descriptor payload contains Wasm module target bytes");

    let text = diagnostic.render();
    assert!(
        text.contains("= help:") && text.contains("target bytes"),
        "text renderer should expose actionable public help metadata\n{text}"
    );

    let json = diagnostic
        .render_json_pretty()
        .expect("diagnostic JSON should serialize");
    let value: serde_json::Value =
        serde_json::from_str(&json).expect("diagnostic JSON should parse");
    assert_eq!(
        value["schema_version"],
        laniusc::compiler::DIAGNOSTIC_JSON_SCHEMA_VERSION
    );
    assert_eq!(
        value["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(value["code"], "LNC0022");
    assert_eq!(value["category"], "native codegen");
    assert_eq!(value["primary_label_policy"], "required");
    assert!(
        value["help"]
            .as_str()
            .expect("JSON diagnostic should include help metadata")
            .contains("target bytes")
    );

    let lsp_json = diagnostic
        .render_lsp_json_pretty()
        .expect("LSP diagnostic JSON should serialize");
    let lsp: serde_json::Value =
        serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
    assert_eq!(lsp["code"], "LNC0022");
    assert_eq!(lsp["data"]["category"], "native codegen");
    assert!(
        lsp["data"]["help"]
            .as_str()
            .expect("LSP diagnostic data should include help metadata")
            .contains("target bytes")
    );
    assert!(lsp.get("help").is_none());
}

#[test]
fn diagnostic_renderers_expose_public_help_metadata_for_source_root_package_boundary() {
    let diagnostic = laniusc::compiler::Diagnostic::error(
        "LNC0024",
        "source-root package boundary for app::leaf",
    )
    .with_primary_label(laniusc::compiler::DiagnosticLabel::primary(
        "core/shim.lani",
        2,
        1,
        "import app::leaf;".len(),
        Some("import app::leaf;".to_string()),
        "stdlib import targets a user source root",
    ))
    .with_note("user candidate: package: app/leaf.lani");

    let text = diagnostic.render();
    assert!(
        text.contains("= help:") && text.contains("package manifest/lockfile metadata"),
        "text renderer should expose package-boundary recovery guidance\n{text}"
    );

    let json = diagnostic
        .render_json_pretty()
        .expect("diagnostic JSON should serialize");
    let value: serde_json::Value =
        serde_json::from_str(&json).expect("diagnostic JSON should parse");
    assert_eq!(value["code"], "LNC0024");
    assert_eq!(value["category"], "package/import loading");
    assert!(
        value["help"]
            .as_str()
            .expect("JSON diagnostic should include package-boundary help")
            .contains("package manifest/lockfile metadata")
    );

    let lsp_json = diagnostic
        .render_lsp_json_pretty()
        .expect("LSP diagnostic JSON should serialize");
    let lsp: serde_json::Value =
        serde_json::from_str(&lsp_json).expect("LSP diagnostic JSON should parse");
    assert_eq!(lsp["code"], "LNC0024");
    assert_eq!(lsp["data"]["category"], "package/import loading");
    assert!(
        lsp["data"]["help"]
            .as_str()
            .expect("LSP diagnostic data should include package-boundary help")
            .contains("package manifest/lockfile metadata")
    );
}

#[test]
fn cli_single_file_assignment_mismatch_renders_stable_diagnostic() {
    assert_assignment_mismatch_diagnostic("x86_64");
}

#[test]
fn cli_check_assignment_mismatch_json_reports_public_type_context_without_stdout() {
    let source = "fn main() {\n    let value: i32 = false;\n    return 0;\n}\n";
    let artifact = common::TempArtifact::new(
        "laniusc_cli_diagnostics",
        "check_assignment_mismatch_json",
        Some("lani"),
    );
    artifact.write_str(source);

    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg("--diagnostic-format=json")
        .arg("--emit")
        .arg("x86_64")
        .arg(artifact.path());
    let output = command_output_with_timeout(
        "laniusc check x86_64 JSON assignment mismatch diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "assignment mismatch should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "check should not write target bytes when type checking fails\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0006");
    assert_eq!(diagnostic["title"], "type mismatch");
    assert_eq!(diagnostic["category"], "type checking");
    assert_eq!(diagnostic["message"], "type mismatch");
    assert_eq!(
        diagnostic["primary_label"]["path"],
        artifact.path().display().to_string()
    );
    assert_eq!(diagnostic["primary_label"]["line"], 2);
    assert_eq!(
        diagnostic["primary_label"]["message"],
        "value type is bool but this context expects i32"
    );
    let byte_start = diagnostic["primary_label"]["byte_start"]
        .as_u64()
        .and_then(|offset| usize::try_from(offset).ok())
        .expect("JSON primary label should expose a source byte_start");
    let byte_end = diagnostic["primary_label"]["byte_end"]
        .as_u64()
        .and_then(|offset| usize::try_from(offset).ok())
        .expect("JSON primary label should expose a source byte_end");
    assert!(
        byte_start < byte_end && byte_end <= source.len(),
        "byte span should be a non-empty range inside the input source: {byte_start}..{byte_end}"
    );

    let notes = diagnostic["notes"]
        .as_array()
        .expect("type mismatch diagnostic should include public notes");
    assert!(
        notes.iter().any(|note| {
            note.as_str().is_some_and(|note| {
                note.contains("expected i32")
                    && note.contains("found bool")
                    && note.contains("change the expression or the annotation")
            })
        }),
        "type mismatch diagnostic should include public expected/found guidance\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("type code")
            && !stderr.contains("GPU type check")
            && !stderr.contains("GpuTypeCheck"),
        "JSON diagnostic should not expose internal type-checker details\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_check_unknown_type_json_reports_public_type_context_without_stdout() {
    let source = concat!(
        "fn keep<T>(value: T) -> T where T: MissingTrait<T> {\n",
        "    return value;\n",
        "}\n",
        "fn main() {\n",
        "    let value: i32 = keep(1);\n",
        "    return value;\n",
        "}\n",
    );
    let artifact = common::TempArtifact::new(
        "laniusc_cli_diagnostics",
        "check_unknown_type_json",
        Some("lani"),
    );
    artifact.write_str(source);

    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg("--diagnostic-format=json")
        .arg("--emit")
        .arg("x86_64")
        .arg(artifact.path());
    let output = command_output_with_timeout(
        "laniusc check x86_64 JSON unknown type diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "unknown type should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "check should not write target bytes when type checking fails\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0007");
    assert_eq!(diagnostic["title"], "unknown type");
    assert_eq!(diagnostic["category"], "type checking");
    assert_eq!(diagnostic["message"], "unknown type");
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0007"
    );

    let primary_label = diagnostic["primary_label"]
        .as_object()
        .expect("unknown-type diagnostic should include a primary label");
    assert_eq!(primary_label["path"], artifact.path().display().to_string());
    assert_eq!(primary_label["line"], 1);
    assert_eq!(primary_label["message"], "type not found");

    let source_line = primary_label["source_line"]
        .as_str()
        .expect("unknown-type diagnostic should include source context");
    let column = primary_label["column"]
        .as_u64()
        .and_then(|column| usize::try_from(column).ok())
        .expect("unknown-type diagnostic should expose a source column");
    let length = primary_label["length"]
        .as_u64()
        .and_then(|length| usize::try_from(length).ok())
        .expect("unknown-type diagnostic should expose a source span length");
    let span_start = column.checked_sub(1).expect("source columns are one-based");
    let span_end = span_start.saturating_add(length).min(source_line.len());
    assert!(
        span_start < span_end && span_end <= source_line.len(),
        "unknown-type span should be a non-empty range inside the source line: {span_start}..{span_end}"
    );
    assert!(
        source_line[span_start..span_end].contains("MissingTrait"),
        "unknown-type span should identify the missing type name"
    );

    let byte_start = primary_label["byte_start"]
        .as_u64()
        .and_then(|offset| usize::try_from(offset).ok())
        .expect("JSON primary label should expose a source byte_start");
    let byte_end = primary_label["byte_end"]
        .as_u64()
        .and_then(|offset| usize::try_from(offset).ok())
        .expect("JSON primary label should expose a source byte_end");
    assert!(
        byte_start < byte_end && byte_end <= source.len(),
        "byte span should be a non-empty range inside the input source: {byte_start}..{byte_end}"
    );
    assert!(
        source[byte_start..byte_end].contains("MissingTrait"),
        "byte span should identify the missing type name"
    );

    let notes = diagnostic["notes"]
        .as_array()
        .expect("unknown-type diagnostic should include public notes");
    assert!(
        notes.iter().any(|note| {
            note.as_str().is_some_and(|note| {
                note.contains("declare the type before using it")
                    && note.contains("import its defining module")
            })
        }),
        "unknown-type diagnostic should include public declaration/import guidance\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("GPU")
            && !stderr.contains("GpuTypeCheck")
            && !stderr.contains("shader")
            && !stderr.contains("source pack")
            && !stderr.contains("internal")
            && !stderr.contains("type code"),
        "unknown-type diagnostic should not expose compiler internals\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_check_unimported_qualified_value_json_reports_public_name_context_without_stdout() {
    let root = common::temp_artifact_path(
        "laniusc_cli_diagnostics",
        "unimported_qualified_value_json",
        None,
    );
    let source_root = root.join("src");
    let app_root = source_root.join("app");
    fs::create_dir_all(&app_root).expect("create source-root app directory");
    let util_path = app_root.join("util.lani");
    let entry_path = app_root.join("main.lani");
    fs::write(
        &util_path,
        "module app::util;\npub fn answer() -> i32 {\n    return 42;\n}\n",
    )
    .expect("write utility module");
    let entry_source = concat!(
        "module app::main;\n",
        "fn main() {\n",
        "    let value: i32 = app::util::answer();\n",
        "    return value;\n",
        "}\n",
    );
    fs::write(&entry_path, entry_source).expect("write source-root entry file");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg("--diagnostic-format=json")
        .arg("--source-root")
        .arg(&source_root)
        .arg(&entry_path);
    let output = command_output_with_timeout(
        "laniusc check JSON unimported qualified value diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");
    fs::remove_dir_all(&root).expect("remove temp source root");

    assert!(
        !output.status.success(),
        "qualified value without an import edge should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "check should not write target bytes when name resolution fails\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0005");
    assert_eq!(diagnostic["title"], "unresolved identifier");
    assert_eq!(diagnostic["category"], "name resolution");
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0005"
    );
    assert_eq!(
        diagnostic["primary_label"]["path"],
        entry_path.display().to_string()
    );
    assert_eq!(diagnostic["primary_label"]["line"], 3);
    assert_eq!(
        diagnostic["primary_label"]["source_line"],
        "    let value: i32 = app::util::answer();"
    );
    assert_eq!(
        diagnostic["primary_label"]["message"],
        "not found in this scope"
    );

    let source_line = diagnostic["primary_label"]["source_line"]
        .as_str()
        .expect("name-resolution diagnostic should include source context");
    let column = diagnostic["primary_label"]["column"]
        .as_u64()
        .and_then(|column| usize::try_from(column).ok())
        .expect("name-resolution diagnostic should expose a source column");
    let length = diagnostic["primary_label"]["length"]
        .as_u64()
        .and_then(|length| usize::try_from(length).ok())
        .expect("name-resolution diagnostic should expose a source span length");
    let span_start = column.checked_sub(1).expect("source columns are one-based");
    let span_end = span_start.saturating_add(length).min(source_line.len());
    let path_start = source_line
        .find("app::util::answer")
        .expect("fixture should contain the qualified value path");
    let path_end = path_start + "app::util::answer".len();
    assert!(
        span_start < span_end && span_start < path_end && path_start < span_end,
        "primary label span should overlap the unimported qualified value path: {span_start}..{span_end}"
    );

    let notes = diagnostic["notes"]
        .as_array()
        .expect("name-resolution diagnostic should include public notes");
    assert!(
        notes.iter().any(|note| {
            note.as_str().is_some_and(|note| {
                note.contains("declare the value before using it")
                    && note.contains("import its defining module")
            })
        }),
        "name-resolution diagnostic should include public import guidance\nstderr:\n{stderr}"
    );

    let mut explain_command = Command::new(laniusc_bin());
    explain_command
        .arg("diagnostics")
        .arg("explain")
        .arg("LNC0005");
    let explanation_output = command_output_with_timeout(
        "laniusc diagnostics explain LNC0005",
        &mut explain_command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics explain");
    assert!(
        explanation_output.status.success(),
        "diagnostics explain should succeed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&explanation_output.stdout),
        String::from_utf8_lossy(&explanation_output.stderr)
    );
    assert!(
        explanation_output.stderr.is_empty(),
        "diagnostics explain should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&explanation_output.stderr)
    );
    let explanation: serde_json::Value = serde_json::from_slice(&explanation_output.stdout)
        .expect("explanation output should be JSON");
    assert_eq!(explanation["known"], true);
    assert_eq!(explanation["diagnostic"]["code"], "LNC0005");
    assert_eq!(explanation["diagnostic"]["category"], "name resolution");

    assert!(
        !stderr.contains("GPU")
            && !stderr.contains("GpuTypeCheck")
            && !stderr.contains("shader")
            && !stderr.contains("source pack")
            && !stderr.contains("internal")
            && !stderr.contains("type code"),
        "name-resolution diagnostic should not expose compiler internals\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_check_call_arity_mismatch_json_reports_public_call_context_without_stdout() {
    let source = concat!(
        "fn add(left: i32, right: i32) -> i32 {\n",
        "    return left + right;\n",
        "}\n",
        "\n",
        "fn main() {\n",
        "    return add(1);\n",
        "}\n",
    );
    let artifact = common::TempArtifact::new(
        "laniusc_cli_diagnostics",
        "check_call_arity_mismatch_json",
        Some("lani"),
    );
    artifact.write_str(source);

    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg("--diagnostic-format=json")
        .arg("--emit")
        .arg("x86_64")
        .arg(artifact.path());
    let output = command_output_with_timeout(
        "laniusc check x86_64 JSON call arity diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "call arity mismatch should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "check should not write target bytes when call resolution fails\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0027");
    assert_eq!(diagnostic["title"], "call resolution failed");
    assert_eq!(diagnostic["category"], "type checking");
    assert_eq!(diagnostic["message"], "call resolution failed");
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0027"
    );

    let primary_label = diagnostic["primary_label"]
        .as_object()
        .expect("call-resolution diagnostic should include a primary label");
    assert_eq!(primary_label["path"], artifact.path().display().to_string());
    assert_eq!(primary_label["line"], 6);
    assert_eq!(
        primary_label["message"],
        "call does not match a resolved function or method"
    );
    assert!(
        primary_label["source_line"]
            .as_str()
            .is_some_and(|line| !line.trim().is_empty()),
        "call-resolution diagnostic should include source context"
    );
    assert!(
        primary_label["column"]
            .as_u64()
            .is_some_and(|column| column > 0),
        "call-resolution diagnostic should expose a one-based source column"
    );
    assert!(
        primary_label["length"]
            .as_u64()
            .is_some_and(|length| length > 0),
        "call-resolution diagnostic should expose a non-empty source span"
    );

    let notes = diagnostic["notes"]
        .as_array()
        .expect("call-resolution diagnostic should include public notes");
    assert!(
        notes.iter().any(|note| {
            note.as_str()
                .is_some_and(|note| note.contains("signature") && note.contains("argument list"))
        }),
        "call-resolution diagnostic should include public signature guidance\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("GPU")
            && !stderr.contains("GpuTypeCheck")
            && !stderr.contains("shader")
            && !stderr.contains("source pack")
            && !stderr.contains("internal")
            && !stderr.contains("type code"),
        "call-resolution diagnostic should not expose compiler internals\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_check_valid_source_suppresses_target_bytes() {
    let artifact = common::TempArtifact::new(
        "laniusc_cli_diagnostics",
        "check_valid_source",
        Some("lani"),
    );
    artifact.write_str("fn main() {\n    return 0;\n}\n");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg("--emit")
        .arg("x86_64")
        .arg(artifact.path());
    let output = command_output_with_timeout(
        "laniusc check x86_64 valid source",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        output.status.success(),
        "check should succeed for valid source\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "check should not write target bytes to stdout\nstdout bytes: {}",
        output.stdout.len()
    );
    assert!(
        output.stderr.is_empty(),
        "check should not print diagnostics for valid source\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn cli_single_file_syntax_error_renders_stable_diagnostic() {
    let source = "fn fn main() { return 0; }\n";
    let artifact = common::TempArtifact::new(
        "laniusc_cli_diagnostics",
        "syntax_duplicate_fn_keyword",
        Some("lani"),
    );
    artifact.write_str(source);

    let mut command = Command::new(laniusc_bin());
    command.arg("--emit").arg("x86_64").arg(artifact.path());
    let output = command_output_with_timeout(
        "laniusc x86_64 single-file syntax error",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "syntax error should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("error[LNC0016]: syntax error"),
        "stderr should contain the stable syntax diagnostic\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains(&artifact.path().display().to_string()),
        "stderr should include the source path\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("fn fn main() { return 0; }"),
        "stderr should include source context\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("^"),
        "stderr should include a source caret\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("invalid syntax here"),
        "stderr should include the primary parser label\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("GPU syntax error"),
        "stderr should not expose the raw GPU syntax wrapper\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("GPU type check error"),
        "stderr should not expose the raw GPU HIR rejection\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_single_file_syntax_error_can_render_json_diagnostic() {
    let source = "fn fn main() { return 0; }\n";
    let artifact = common::TempArtifact::new(
        "laniusc_cli_diagnostics",
        "syntax_duplicate_fn_keyword_json",
        Some("lani"),
    );
    artifact.write_str(source);

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--diagnostic-format=json")
        .arg("--emit")
        .arg("x86_64")
        .arg(artifact.path());
    let output = command_output_with_timeout(
        "laniusc x86_64 JSON syntax diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "syntax error should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0016");
    assert_eq!(diagnostic["title"], "syntax error");
    assert_eq!(diagnostic["category"], "parsing");
    assert_eq!(diagnostic["message"], "syntax error");
    assert_eq!(
        diagnostic["primary_label"]["path"],
        artifact.path().display().to_string()
    );
    assert_eq!(diagnostic["primary_label"]["line"], 1);
    assert_eq!(
        diagnostic["primary_label"]["source_line"],
        "fn fn main() { return 0; }"
    );
    assert_eq!(
        diagnostic["primary_label"]["message"],
        "invalid syntax here"
    );
    let byte_start = diagnostic["primary_label"]["byte_start"]
        .as_u64()
        .and_then(|offset| usize::try_from(offset).ok())
        .expect("JSON primary label should expose a source byte_start");
    let byte_end = diagnostic["primary_label"]["byte_end"]
        .as_u64()
        .and_then(|offset| usize::try_from(offset).ok())
        .expect("JSON primary label should expose a source byte_end");
    assert!(
        byte_start < byte_end && byte_end <= source.len(),
        "byte span should be a non-empty range inside the input source: {byte_start}..{byte_end}"
    );
    assert!(
        source[byte_start..byte_end]
            .bytes()
            .all(|byte| byte != b'\n'),
        "byte span should identify source on the primary label line"
    );
}

#[test]
fn cli_check_syntax_error_can_render_json_diagnostic_without_stdout() {
    let source = "fn fn main() { return 0; }\n";
    let artifact = common::TempArtifact::new(
        "laniusc_cli_diagnostics",
        "check_syntax_duplicate_fn_keyword_json",
        Some("lani"),
    );
    artifact.write_str(source);

    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg("--diagnostic-format=json")
        .arg("--emit")
        .arg("x86_64")
        .arg(artifact.path());
    let output = command_output_with_timeout(
        "laniusc check x86_64 JSON syntax diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "syntax error should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "check should not write target bytes when diagnostics fail\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0016");
    assert_eq!(diagnostic["message"], "syntax error");
    assert_eq!(
        diagnostic["primary_label"]["path"],
        artifact.path().display().to_string()
    );
    assert_eq!(
        diagnostic["primary_label"]["source_line"],
        source.trim_end()
    );
}

#[test]
fn cli_check_syntax_error_can_render_lsp_json_diagnostic_without_stdout() {
    let source = "fn fn main() { return 0; }\n";
    let artifact = common::TempArtifact::new(
        "laniusc_cli_diagnostics",
        "check_syntax_duplicate_fn_keyword_lsp_json",
        Some("lani"),
    );
    artifact.write_str(source);

    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg("--diagnostic-format=lsp-json")
        .arg("--emit")
        .arg("x86_64")
        .arg(artifact.path());
    let output = command_output_with_timeout(
        "laniusc check x86_64 LSP JSON syntax diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "syntax error should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "check should not write target bytes when diagnostics fail\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        !stderr.contains("laniusc:"),
        "LSP JSON diagnostics should not include the text CLI prefix\nstderr:\n{stderr}"
    );
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one LSP diagnostic object");
    assert_eq!(diagnostic["severity"], 1);
    assert_eq!(diagnostic["code"], "LNC0016");
    assert_eq!(diagnostic["source"], "laniusc");
    assert_eq!(diagnostic["message"], "syntax error");
    assert_eq!(
        diagnostic["data"]["schema_version"],
        laniusc::compiler::LSP_DIAGNOSTIC_DATA_SCHEMA_VERSION
    );
    assert_eq!(
        diagnostic["data"]["registry_schema_version"],
        laniusc::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(diagnostic["data"]["title"], "syntax error");
    assert_eq!(diagnostic["data"]["category"], "parsing");
    assert_eq!(diagnostic["data"]["primary_label_policy"], "required");
    assert_eq!(
        diagnostic["data"]["explain_command"],
        "laniusc diagnostics explain LNC0016"
    );
    assert_eq!(
        diagnostic["data"]["primary_label"]["path"],
        artifact.path().display().to_string()
    );
    assert_eq!(diagnostic["data"]["primary_label"]["line"], 1);
    assert_eq!(
        diagnostic["data"]["primary_label"]["message"],
        "invalid syntax here"
    );
    assert!(diagnostic["range"]["start"]["line"].is_number());
    assert!(diagnostic["range"]["start"]["character"].is_number());
    assert!(diagnostic["range"]["end"]["line"].is_number());
    assert!(diagnostic["range"]["end"]["character"].is_number());
    assert!(diagnostic.get("primary_label").is_none());
    assert!(diagnostic.get("notes").is_none());
    assert!(diagnostic.get("diagnostics").is_none());
}

#[test]
fn cli_check_source_root_missing_import_renders_json_category_before_compiling_source() {
    let root = common::temp_artifact_path(
        "laniusc_cli_diagnostics",
        "source_root_missing_import_json",
        None,
    );
    let source_root = root.join("src");
    let app_root = source_root.join("app");
    fs::create_dir_all(&app_root).expect("create source-root app directory");
    let entry_path = app_root.join("main.lani");
    let entry_source = "module app::main;\nimport app::missing;\nfn main() { return 0; }\n";
    fs::write(&entry_path, entry_source).expect("write source-root entry file");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("check")
        .arg("--diagnostic-format=json")
        .arg("--source-root")
        .arg(&source_root)
        .arg(&entry_path);
    let output = command_output_with_timeout(
        "laniusc check JSON source-root missing import diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");
    fs::remove_dir_all(&root).expect("remove temp source root");

    assert!(
        !output.status.success(),
        "missing source-root import should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "check should not write target bytes when import loading fails\nstdout bytes: {}",
        output.stdout.len()
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    let diagnostic: serde_json::Value =
        serde_json::from_str(&stderr).expect("stderr should be one JSON diagnostic object");
    assert_eq!(diagnostic["severity"], "error");
    assert_eq!(diagnostic["code"], "LNC0001");
    assert_eq!(diagnostic["title"], "missing source-root module");
    assert_eq!(diagnostic["category"], "package/import loading");
    assert_eq!(
        diagnostic["explain_command"],
        "laniusc diagnostics explain LNC0001"
    );
    let message = diagnostic["message"]
        .as_str()
        .expect("diagnostic message should be a string");
    assert!(message.starts_with("missing source-root module"));
    assert!(message.contains("app::missing"));

    let primary_label = diagnostic["primary_label"]
        .as_object()
        .expect("missing import diagnostic should include a primary label");
    assert_eq!(
        primary_label["path"],
        entry_path.display().to_string(),
        "primary label should point at the importing entry file"
    );
    assert_eq!(primary_label["line"], 2);
    assert_eq!(primary_label["source_line"], "import app::missing;");
    assert_eq!(primary_label["message"], "imported here");
    let column = primary_label["column"]
        .as_u64()
        .and_then(|column| usize::try_from(column).ok())
        .expect("missing import diagnostic should expose a source column");
    let length = primary_label["length"]
        .as_u64()
        .and_then(|length| usize::try_from(length).ok())
        .expect("missing import diagnostic should expose a source span length");
    let source_line = primary_label["source_line"]
        .as_str()
        .expect("missing import diagnostic should include source context");
    let span_start = column.checked_sub(1).expect("source columns are one-based");
    let span_end = span_start.saturating_add(length).min(source_line.len());
    assert!(
        span_start < span_end && span_end <= source_line.len(),
        "missing import span should be a non-empty range inside the source line: {span_start}..{span_end}"
    );
    assert!(
        source_line[span_start..span_end].contains("app::missing"),
        "missing import span should identify the unresolved module path"
    );

    let notes = diagnostic["notes"]
        .as_array()
        .expect("missing import diagnostic should include notes");
    assert!(
        notes.iter().any(|note| {
            note.as_str().is_some_and(|note| {
                note.starts_with("searched ") && note.contains("app/missing.lani")
            })
        }),
        "diagnostic notes should identify searched source-root candidates\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("GPU")
            && !stderr.contains("shader")
            && !stderr.contains("source pack")
            && !stderr.contains("internal"),
        "missing import diagnostic should not expose internal compiler details\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_source_root_import_syntax_error_renders_stable_file_diagnostic() {
    let source_root =
        common::temp_artifact_path("laniusc_cli_diagnostics", "source_root_syntax", None);
    let app_root = source_root.join("app");
    fs::create_dir_all(&app_root).expect("create source-root app directory");
    let entry_path = app_root.join("main.lani");
    let bad_path = app_root.join("bad.lani");
    fs::write(
        &entry_path,
        "module app::main;\nimport app::bad;\nfn main() { return 0; }\n",
    )
    .expect("write source-root entry file");
    fs::write(
        &bad_path,
        "module app::bad;\nfn fn bad() -> i32 { return 1; }\n",
    )
    .expect("write malformed imported source-root file");

    let mut command = Command::new(laniusc_bin());
    command
        .arg("--emit")
        .arg("x86_64")
        .arg("--source-root")
        .arg(&source_root)
        .arg(&entry_path);
    let output = command_output_with_timeout(
        "laniusc x86_64 source-root imported syntax error",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");
    fs::remove_dir_all(&source_root).expect("remove temp source root");

    assert!(
        !output.status.success(),
        "source-root syntax error should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("error[LNC0016]: syntax error"),
        "stderr should contain the stable syntax diagnostic\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains(&format!("{}:2:", bad_path.display())),
        "stderr should point at the malformed imported file on line 2\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("^"),
        "stderr should include a source caret\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("invalid syntax here"),
        "stderr should include the primary parser label\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("GPU syntax error"),
        "stderr should not expose the raw GPU syntax wrapper\nstderr:\n{stderr}"
    );
}

fn assert_assignment_mismatch_diagnostic(emit: &str) {
    let source = "fn main() {\n    let value: i32 = false;\n    return 0;\n}\n";
    let artifact = common::TempArtifact::new(
        "laniusc_cli_diagnostics",
        &format!("assign_mismatch_{emit}"),
        Some("lani"),
    );
    artifact.write_str(source);

    let mut command = Command::new(laniusc_bin());
    command.arg("--emit").arg(emit).arg(artifact.path());
    let output = command_output_with_timeout(
        &format!("laniusc {emit} single-file assignment mismatch"),
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc");

    assert!(
        !output.status.success(),
        "{emit} assignment mismatch should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("error[LNC0006]: type mismatch"),
        "stderr should contain the stable assignment mismatch diagnostic\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains(&artifact.path().display().to_string()),
        "stderr should include the source path\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("    let value: i32 = false;"),
        "stderr should include source context\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("^"),
        "stderr should include a source caret\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("value type is bool") && stderr.contains("expects i32"),
        "stderr should include source-facing expected/found type details\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("change the expression or the annotation"),
        "stderr should include a remediation note for the type mismatch\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("type code"),
        "stderr should not expose raw type checker type codes\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("GPU type check rejected"),
        "stderr should not expose the raw GPU rejection\nstderr:\n{stderr}"
    );
}

fn seed_completed_descriptor_root(
    artifact_root: &std::path::Path,
    target: SourcePackArtifactTarget,
    linked_output_key: &str,
) -> PathBuf {
    let store = FilesystemArtifactStore::new(artifact_root);
    store
        .store_build_state_for_target(target, &SourcePackBuildState::new())
        .expect("store source-pack build state marker");

    let progress = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target,
        work_item_count: 0,
        page_size: SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE,
        page_count: 0,
        artifact_item_count: 0,
        completed_item_count: 0,
        ready_item_count: 0,
        ready_artifact_item_count: 0,
        claimed_item_count: 0,
        first_ready_item_index: None,
        first_ready_artifact_item_index: None,
    };
    store
        .store_work_queue_progress_index(&progress)
        .expect("store complete source-pack work queue progress index");

    let link_execution = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target,
        first_link_job_index: 0,
        final_link_group_index: 0,
        final_link_job_index: 0,
        link_group_count: 1,
        final_output_key: linked_output_key.to_string(),
    };
    let link_execution_bytes =
        serde_json::to_vec_pretty(&link_execution).expect("serialize link execution index");
    fs::write(
        store.hierarchical_link_execution_index_path_for_target(target),
        link_execution_bytes,
    )
    .expect("store complete source-pack link execution index");

    let linked_output = store
        .path_for_key(linked_output_key)
        .expect("resolve linked-output artifact path");
    fs::create_dir_all(
        linked_output
            .parent()
            .expect("linked-output artifact path should have a parent"),
    )
    .expect("create linked-output artifact directory");
    linked_output
}

fn command_output_with_timeout(
    context: &str,
    command: &mut Command,
    timeout: Duration,
) -> io::Result<Output> {
    let child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    Ok(child_output_with_timeout(context, child, timeout))
}

fn command_output_with_stdin_timeout(
    context: &str,
    command: &mut Command,
    stdin: &str,
    timeout: Duration,
) -> io::Result<Output> {
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    {
        let child_stdin = child
            .stdin
            .as_mut()
            .expect("stdin should be piped for command");
        child_stdin.write_all(stdin.as_bytes())?;
    }
    drop(child.stdin.take());
    Ok(child_output_with_timeout(context, child, timeout))
}

fn command_output_with_stdin_bytes_timeout(
    context: &str,
    command: &mut Command,
    stdin: &[u8],
    timeout: Duration,
) -> io::Result<Output> {
    let mut child = command
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    {
        let child_stdin = child
            .stdin
            .as_mut()
            .expect("stdin should be piped for command");
        child_stdin.write_all(stdin)?;
    }
    drop(child.stdin.take());
    Ok(child_output_with_timeout(context, child, timeout))
}

fn child_output_with_timeout(context: &str, mut child: Child, timeout: Duration) -> Output {
    let start = Instant::now();

    loop {
        match child.try_wait() {
            Ok(Some(_)) => return child.wait_with_output().expect("collect command output"),
            Ok(None) => {}
            Err(err) => panic!("{context}: wait for command: {err}"),
        }

        if start.elapsed() >= timeout {
            if let Err(err) = child.kill() {
                panic!("{context}: kill timed-out command: {err}");
            }
            let output = child
                .wait_with_output()
                .expect("collect timed-out command output");
            panic!(
                "{context} timed out after {} ms\nstdout:\n{}\nstderr:\n{}",
                timeout.as_millis(),
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
        }

        thread::sleep(CHILD_PROCESS_POLL_INTERVAL);
    }
}
