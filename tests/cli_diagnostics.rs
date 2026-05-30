mod common;

use std::{
    fs,
    io,
    path::PathBuf,
    process::{Command, Output, Stdio},
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

#[test]
fn diagnostic_registry_json_contains_code_metadata_categories_and_unsupported_boundaries() {
    let json = laniusc::compiler::diagnostic_registry_json_pretty()
        .expect("diagnostic registry should serialize");
    let registry: serde_json::Value =
        serde_json::from_str(&json).expect("diagnostic registry JSON should parse");

    assert_eq!(registry["schema_version"], 5);

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
            && feature["next_step"]
                .as_str()
                .expect("unsupported feature next_step should be a string")
                .contains("requires_runtime_binding")
    }));
}

#[test]
fn diagnostic_explain_describes_source_root_package_boundary_recovery() {
    let json = laniusc::compiler::diagnostic_explanation_json_pretty("lnc0024")
        .expect("diagnostic explanation should serialize");
    let explanation: serde_json::Value =
        serde_json::from_str(&json).expect("diagnostic explanation JSON should parse");

    assert_eq!(explanation["requested_code"], "LNC0024");
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
        explanation["unsupported_feature"]["next_step"]
            .as_str()
            .expect("boundary next step should be public text")
            .contains("requires_runtime_binding")
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
            && service["binding_probe"] == "stdio_requires_runtime_binding()"
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
            && api["binding_probe"] == "print_i32_requires_runtime_binding()"
            && api["current_status"] == "known-unbound"
            && api["executable"] == false
    }));
    assert!(runtime_apis.iter().all(|api| {
        api["diagnostic_code"] == "LNC0038"
            && api["current_status"] == "known-unbound"
            && api["executable"] == false
    }));
}

#[test]
fn diagnostic_output_formats_json_describes_cli_payload_contracts() {
    let json = laniusc::compiler::diagnostic_output_formats_json_pretty()
        .expect("diagnostic output formats should serialize");
    let registry: serde_json::Value =
        serde_json::from_str(&json).expect("diagnostic output format JSON should parse");

    assert_eq!(registry["schema_version"], 6);
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

    let formats = registry["formats"]
        .as_array()
        .expect("diagnostic formats should be an array");
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
        json_format["position_encoding"],
        "one-based source line and column"
    );
    assert_eq!(json_format["includes_source_snippet"], true);
    assert_eq!(json_format["language_server_envelope"], false);
    assert_eq!(json_format["check_mode_supported"], true);
    assert_eq!(json_format["formatter_check_supported"], true);
    assert!(
        json_format["description"]
            .as_str()
            .expect("JSON format description should be a string")
            .contains("schema version"),
        "JSON format description should advertise stable payload version metadata"
    );
    assert!(
        json_format["description"]
            .as_str()
            .expect("JSON format description should be a string")
            .contains("primary-label policy"),
        "JSON format description should advertise registry-backed primary-label policy metadata"
    );

    let lsp_json_format = formats
        .iter()
        .find(|format| format["name"] == "lsp-json")
        .expect("LSP JSON diagnostic format should be listed");
    assert_eq!(lsp_json_format["output_stream"], "stderr");
    assert_eq!(lsp_json_format["payload"], "LSP Diagnostic JSON object");
    assert_eq!(lsp_json_format["position_encoding"], "utf-16");
    assert_eq!(lsp_json_format["includes_source_snippet"], false);
    assert_eq!(lsp_json_format["language_server_envelope"], false);
    assert_eq!(lsp_json_format["check_mode_supported"], true);
    assert_eq!(lsp_json_format["formatter_check_supported"], true);
    assert!(
        lsp_json_format["description"]
            .as_str()
            .expect("LSP JSON format description should be a string")
            .contains("versioned Lanius"),
        "LSP JSON format description should advertise stable versioned data metadata"
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
    assert_eq!(registry["schema_version"], 5);
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
                        .is_some_and(|next_step| next_step.contains("requires_runtime_binding"))
            }),
        "registry command should expose runtime-service boundary metadata\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
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
    assert_eq!(document["schema_version"], 1);
    assert_eq!(document["registry_schema_version"], 5);
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);

    let categories = document["categories"]
        .as_array()
        .expect("categories should be an array");
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
            && code["primary_label_policy"] == "none"
            && code["default_severity"] == "error"
            && code["lsp_source"] == "laniusc"
            && code["lsp_severity"] == 1
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
        .arg("wasm");
    let output = command_output_with_timeout(
        "laniusc diagnostics source-pack-progress",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc diagnostics source-pack-progress");

    assert!(
        output.status.success(),
        "source-pack progress diagnostics should succeed\nstdout:\n{}\nstderr:\n{}",
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
    assert_eq!(document["guards"]["source_compilation"], false);
    assert_eq!(document["guards"]["source_scanning"], false);
    assert_eq!(document["guards"]["gpu_device_creation"], false);
    assert_eq!(document["guards"]["target_codegen"], false);
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
    assert_eq!(registry["schema_version"], 6);
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

    let formats = registry["formats"]
        .as_array()
        .expect("diagnostic formats should be an array");
    assert!(formats.iter().any(|format| {
        format["name"] == "text"
            && format["output_stream"] == "stderr"
            && format["includes_source_snippet"] == true
            && format["formatter_check_supported"] == true
    }));
    assert!(formats.iter().any(|format| {
        format["name"] == "lsp-json"
            && format["payload"] == "LSP Diagnostic JSON object"
            && format["position_encoding"] == "utf-16"
            && format["language_server_envelope"] == false
            && format["formatter_check_supported"] == true
            && format["description"]
                .as_str()
                .is_some_and(|description| description.contains("versioned Lanius"))
    }));
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
    assert_eq!(explanation["registry_schema_version"], 5);
    assert_eq!(explanation["requested_code"], "LNC0017");
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
    assert!(explanation["runtime_service_boundaries"].is_null());
    assert!(explanation["runtime_bound_apis"].is_null());
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
            && service["binding_probe"] == "test_harness_requires_runtime_binding()"
    }));
    assert!(services.iter().all(|service| {
        service["diagnostic_code"] == "LNC0038"
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
            && api["executable_probe"] == "print_i32_is_executable()"
            && api["binding_probe"] == "print_i32_requires_runtime_binding()"
            && api["executable"] == false
    }));
    assert!(apis.iter().all(|api| {
        api["diagnostic_code"] == "LNC0038"
            && api["current_status"] == "known-unbound"
            && api["executable"] == false
    }));
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
    assert_eq!(diagnostic["message"], "missing CLI argument");
    assert!(diagnostic["primary_label"].is_null());
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
    command.arg("diagnostics").arg("explain").arg("LNC9999");
    let output = command_output_with_timeout(
        "laniusc diagnostics explain LNC9999",
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
    assert_eq!(explanation["registry_schema_version"], 5);
    assert_eq!(explanation["requested_code"], "LNC9999");
    assert_eq!(explanation["known"], false);
    assert!(explanation["diagnostic"].is_null());
    assert!(explanation["unsupported_feature"].is_null());
    assert!(explanation["runtime_service_boundaries"].is_null());
    assert!(explanation["runtime_bound_apis"].is_null());
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
    assert_eq!(diagnostic["code"], "LNC0020");
    assert_eq!(diagnostic["title"], "unknown CLI option");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unknown CLI option");
    assert!(diagnostic["primary_label"].is_null());
    let notes = diagnostic["notes"]
        .as_array()
        .expect("unknown diagnostics subcommand should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc diagnostics")),
        "diagnostic notes should identify the diagnostics command\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("registry, categories, formats, explain")),
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
fn cli_fmt_extra_input_can_render_json_diagnostic_without_reading_files() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("fmt")
        .arg("--diagnostic-format=json")
        .arg("first.lani")
        .arg("second.lani");
    let output = command_output_with_timeout(
        "laniusc fmt JSON unexpected input diagnostic",
        &mut command,
        CLI_DIAGNOSTIC_TIMEOUT,
    )
    .expect("spawn laniusc fmt");

    assert!(
        !output.status.success(),
        "extra fmt input should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        output.stdout.is_empty(),
        "extra fmt input should not write stdout bytes\nstdout bytes: {}",
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
        .expect("unexpected fmt argument diagnostic should include notes");
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("laniusc fmt")),
        "diagnostic notes should identify the fmt command\nstderr:\n{stderr}"
    );
    assert!(
        notes.iter().any(|note| note
            .as_str()
            .expect("diagnostic note should be a string")
            .contains("second.lani")),
        "diagnostic notes should include the unexpected input path\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_lsp_unknown_subcommand_can_render_json_diagnostic() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("lsp")
        .arg("--diagnostic-format=json")
        .arg("serve");
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
    assert_eq!(diagnostic["code"], "LNC0020");
    assert_eq!(diagnostic["title"], "unknown CLI option");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unknown CLI option");
    assert!(diagnostic["primary_label"].is_null());
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
            .contains("wasm, x86_64")),
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
            .contains("wasm, x86_64")),
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
    assert_eq!(diagnostic["code"], "LNC0020");
    assert_eq!(diagnostic["title"], "unknown CLI option");
    assert_eq!(diagnostic["category"], "tooling");
    assert_eq!(diagnostic["message"], "unknown CLI option");
    assert!(diagnostic["primary_label"].is_null());
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
    assert_eq!(diagnostic["data"]["registry_schema_version"], 5);
    assert_eq!(diagnostic["data"]["position_encoding"], "utf-16");
    assert_eq!(diagnostic["data"]["title"], "unsupported CLI option value");
    assert_eq!(diagnostic["data"]["category"], "tooling");
    assert_eq!(diagnostic["data"]["primary_label_policy"], "none");
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
    assert_eq!(registry["schema_version"], 5);
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
    assert_eq!(formats["schema_version"], 6);
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
    assert_eq!(explanation["known"], true);
    assert_eq!(explanation["diagnostic"]["code"], "LNC0017");
}

#[test]
fn cli_no_run_diagnostic_help_advertises_machine_readable_invocation_diagnostics() {
    for (context, args, expected_usages) in [
        (
            "laniusc diagnostics --help",
            &["diagnostics", "--help"][..],
            &[
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] registry",
                "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] explain CODE",
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
    let linked_output_key = "wasm/linked-output/final-output.contract";
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
    let linked_output_key = "wasm/linked-output/final-output.contract";
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
    assert_eq!(diagnostic["data"]["registry_schema_version"], 5);
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
    assert_eq!(value["data"]["registry_schema_version"], 5);
    assert_eq!(value["data"]["title"], "syntax error");
    assert_eq!(value["data"]["category"], "parsing");
    assert_eq!(value["data"]["primary_label_policy"], "required");
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
    assert_eq!(value["data"]["registry_schema_version"], 5);
    assert_eq!(value["data"]["title"], "syntax error");
    assert_eq!(value["data"]["category"], "parsing");
    assert_eq!(value["data"]["primary_label_policy"], "required");
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
    assert_eq!(diagnostic["data"]["registry_schema_version"], 5);
    assert_eq!(diagnostic["data"]["title"], "syntax error");
    assert_eq!(diagnostic["data"]["category"], "parsing");
    assert_eq!(diagnostic["data"]["primary_label_policy"], "required");
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
    fs::write(
        &entry_path,
        "module app::main;\nimport app::missing;\nfn main() { return 0; }\n",
    )
    .expect("write source-root entry file");

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
    assert_eq!(diagnostic["category"], "package/import loading");
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
    assert!(primary_label["column"].is_number());
    assert!(primary_label["length"].is_number());
    assert!(primary_label["message"].is_string());

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
        stderr.contains("fn fn bad() -> i32 { return 1; }"),
        "stderr should include malformed imported source context\nstderr:\n{stderr}"
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
    let mut child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let start = Instant::now();

    loop {
        match child.try_wait() {
            Ok(Some(_)) => return Ok(child.wait_with_output().expect("collect command output")),
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
