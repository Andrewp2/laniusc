mod common;

use std::{
    collections::BTreeMap,
    env,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

#[test]
fn cli_version_reports_distribution_contract_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--version")
        .arg("--emit=not-a-real-target")
        .arg("/definitely/not/a/source/file.lani");

    let output = common::command_output_with_timeout("laniusc --version", &mut command);
    common::assert_command_success("laniusc --version", &output);

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.is_empty(),
        "--version should not print diagnostics\nstderr:\n{stderr}"
    );
    let mut lines = stdout.lines();
    assert_eq!(
        lines.next(),
        Some(format!("laniusc {}", env!("CARGO_PKG_VERSION")).as_str()),
        "--version should start with the compiler package version\nstdout:\n{stdout}"
    );

    let fields = parse_version_fields(lines, &stdout);
    assert_eq!(
        fields.get("language-edition").map(String::as_str),
        Some("unstable-alpha"),
        "--version should name the current language edition\nstdout:\n{stdout}"
    );
    assert_field_contains(
        &fields,
        "edition-policy",
        "no stable production language edition yet",
        &stdout,
    );
    assert_eq!(
        fields.get("targets").map(String::as_str),
        Some("x86_64, wasm"),
        "--version should list the accepted emit targets\nstdout:\n{stdout}"
    );
    assert_eq!(
        fields.get("default-target").map(String::as_str),
        Some("x86_64"),
        "--version should publish the default emit target\nstdout:\n{stdout}"
    );
    assert_eq!(
        fields.get("target-triples").map(String::as_str),
        Some("x86_64-unknown-linux-gnu, wasm32-unknown-unknown"),
        "--version should list the accepted target triples\nstdout:\n{stdout}"
    );
    assert_field_contains(
        &fields,
        "x86_64",
        "unsupported source shapes are rejected",
        &stdout,
    );
    assert_eq!(
        fields.get("formatter").map(String::as_str),
        Some("unstable-alpha lexical full-document formatter"),
        "--version should publish the formatter contract\nstdout:\n{stdout}"
    );
    assert_eq!(
        fields.get("release-channel").map(String::as_str),
        Some("source-worktree"),
        "--version should publish the release channel boundary\nstdout:\n{stdout}"
    );
    assert_field_contains(
        &fields,
        "distribution-status",
        "not-production-release",
        &stdout,
    );
    assert_eq!(
        fields
            .get("lsp-capabilities-schema-name")
            .map(String::as_str),
        Some("laniusc.lsp.capabilities"),
        "--version should publish the LSP capabilities schema name\nstdout:\n{stdout}"
    );
    assert_eq!(
        fields.get("lsp-capabilities-schema").map(String::as_str),
        Some("15"),
        "--version should publish the LSP capabilities schema version\nstdout:\n{stdout}"
    );
    assert_eq!(
        fields
            .get("lsp-experimental-schema-name")
            .map(String::as_str),
        Some("laniusc.lsp.experimental"),
        "--version should publish the LSP experimental extension schema name\nstdout:\n{stdout}"
    );
    assert_eq!(
        fields.get("lsp-experimental-schema").map(String::as_str),
        Some("13"),
        "--version should publish the LSP experimental extension schema version\nstdout:\n{stdout}"
    );
    assert_eq!(
        fields.get("lsp-error-data-schema-name").map(String::as_str),
        Some("laniusc.lsp.error-data"),
        "--version should publish the LSP error-data schema name\nstdout:\n{stdout}"
    );
    assert_eq!(
        fields.get("lsp-error-data-schema").map(String::as_str),
        Some("2"),
        "--version should publish the LSP JSON-RPC error-data schema version\nstdout:\n{stdout}"
    );
    for field in [
        "slangc",
        "wgpu",
        "build-profile",
        "shader-artifact-digest",
        "shader-artifact-count",
        "shader-artifact-max-bytes",
        "shader-artifact-max-name",
        "shader-artifact-size-guard",
        "shader-artifact-max-spv-bytes",
        "slangc-version-timeout-ms",
        "shader-compile-timeout-ms",
    ] {
        let value = fields
            .get(field)
            .unwrap_or_else(|| panic!("--version should report {field}\nstdout:\n{stdout}"));
        assert!(
            !value.trim().is_empty() && value != "unknown",
            "--version field {field} should be populated for a built binary\nstdout:\n{stdout}"
        );
    }
    assert!(
        fields["shader-artifact-count"]
            .parse::<u64>()
            .is_ok_and(|count| count > 0),
        "--version should publish a positive shader artifact count\nstdout:\n{stdout}"
    );
    assert!(
        fields["shader-artifact-max-bytes"]
            .parse::<u64>()
            .is_ok_and(|bytes| bytes > 0),
        "--version should publish the largest active shader artifact size\nstdout:\n{stdout}"
    );
    assert!(
        fields["shader-artifact-size-guard"] == "enforced"
            || fields["shader-artifact-size-guard"] == "disabled",
        "--version should publish the shader artifact size guard status\nstdout:\n{stdout}"
    );
    if fields["shader-artifact-size-guard"] == "enforced" {
        let max_artifact_bytes = fields["shader-artifact-max-bytes"]
            .parse::<u64>()
            .expect("max artifact bytes should parse above");
        let guard_max_bytes = fields["shader-artifact-max-spv-bytes"]
            .parse::<u64>()
            .expect("enforced guard max bytes should be numeric");
        assert!(
            max_artifact_bytes <= guard_max_bytes,
            "--version should show the active shader artifact cap covers the largest artifact\nstdout:\n{stdout}"
        );
    }
    assert_timeout_field(&fields, "slangc-version-timeout-ms", "--version", &stdout);
    assert_timeout_field(&fields, "shader-compile-timeout-ms", "--version", &stdout);
}

#[test]
fn cli_version_short_flag_matches_long_flag() {
    let mut long_command = Command::new(laniusc_bin());
    long_command
        .arg("--version")
        .arg("--emit=not-a-real-target")
        .arg("/definitely/not/a/source/file.lani");
    let long_output = common::command_output_with_timeout("laniusc --version", &mut long_command);
    common::assert_command_success("laniusc --version", &long_output);

    let mut short_command = Command::new(laniusc_bin());
    short_command
        .arg("-V")
        .arg("--emit=not-a-real-target")
        .arg("/definitely/not/a/source/file.lani");
    let short_output = common::command_output_with_timeout("laniusc -V", &mut short_command);
    common::assert_command_success("laniusc -V", &short_output);

    assert_eq!(
        short_output.stdout, long_output.stdout,
        "-V should short-circuit to the same version contract as --version"
    );
    assert!(
        long_output.stderr.is_empty(),
        "--version should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&long_output.stderr)
    );
    assert!(
        short_output.stderr.is_empty(),
        "-V should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&short_output.stderr)
    );
}

#[test]
fn cli_doctor_reports_no_run_toolchain_contract_without_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command.arg("doctor").arg("--diagnostic-format=json");

    let output = common::command_output_with_timeout("laniusc doctor", &mut command);
    common::assert_command_success("laniusc doctor", &output);

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.is_empty(),
        "doctor should not print diagnostics on success\nstderr:\n{stderr}"
    );

    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("doctor output should be JSON");
    assert_eq!(document["schema_version"], 12);
    assert!(
        matches!(
            document["status"].as_str(),
            Some("ok") | Some("action-required")
        ),
        "doctor status should summarize local toolchain readiness\nstdout:\n{stdout}"
    );
    assert_eq!(document["compiler"]["name"], "laniusc");
    assert_eq!(document["compiler"]["version"], env!("CARGO_PKG_VERSION"));
    assert_eq!(document["compiler"]["language_edition"], "unstable-alpha");
    assert_eq!(
        document["compiler"]["emit_targets"]
            .as_array()
            .expect("doctor should list emit targets")
            .iter()
            .map(|value| value.as_str().expect("emit target should be a string"))
            .collect::<Vec<_>>(),
        vec!["x86_64", "wasm"]
    );
    assert_eq!(document["compiler"]["default_emit_target"], "x86_64");
    assert_eq!(
        document["distribution"]["release_channel"],
        "source-worktree"
    );
    assert_eq!(
        document["distribution"]["status"],
        "not-production-release; no stable install artifact or package manager channel"
    );
    assert_eq!(document["distribution"]["stable_install_artifact"], false);
    assert_eq!(document["distribution"]["package_manager_channel"], false);
    assert_eq!(document["distribution"]["release_artifact_workflow"], false);
    assert_eq!(
        document["distribution"]["source_control_required_for_claims"],
        true
    );
    assert_eq!(document["distribution"]["production_release_claim"], false);
    assert!(
        document["distribution"]["next_user_gate"]
            .as_str()
            .is_some_and(|gate| gate.contains("create a package")
                && gate.contains("editor diagnostics")
                && gate.contains("run native output")),
        "doctor should publish the external-user release gate\nstdout:\n{stdout}"
    );
    assert!(
        matches!(
            document["toolchain"]["slangc"]["status"].as_str(),
            Some("ok") | Some("missing") | Some("error")
        ),
        "doctor should report Slang availability without requiring it\nstdout:\n{stdout}"
    );
    assert!(
        document["toolchain"]["slangc"]["required"]
            .as_str()
            .is_some_and(|required| !required.trim().is_empty()),
        "doctor should describe why Slang is checked\nstdout:\n{stdout}"
    );
    if let Some(configured_slangc) = env::var_os("SLANGC").filter(|value| !value.is_empty()) {
        let configured_slangc = configured_slangc.to_string_lossy();
        assert_eq!(
            document["toolchain"]["slangc"]["source"], "SLANGC",
            "doctor should honor the configured Slang compiler path\nstdout:\n{stdout}"
        );
        assert_eq!(
            document["toolchain"]["slangc"]["path"].as_str(),
            Some(configured_slangc.as_ref()),
            "doctor should report the configured Slang compiler path\nstdout:\n{stdout}"
        );
        assert_eq!(
            document["toolchain"]["slangc"]["status"], "ok",
            "doctor should use Slang's supported -version probe for the configured compiler\nstdout:\n{stdout}"
        );
    }
    let shader_artifacts = &document["toolchain"]["shader_artifacts"];
    assert!(
        shader_artifacts["digest"]["value"]
            .as_str()
            .is_some_and(|digest| digest != "unknown" && !digest.trim().is_empty()),
        "doctor should publish shader artifact digest metadata\nstdout:\n{stdout}"
    );
    assert!(
        shader_artifacts["count"]
            .as_u64()
            .is_some_and(|count| count > 0),
        "doctor should publish a positive shader artifact count\nstdout:\n{stdout}"
    );
    assert!(
        shader_artifacts["largest"]["name"]
            .as_str()
            .is_some_and(|name| name != "unknown" && name != "none"),
        "doctor should name the largest active shader artifact\nstdout:\n{stdout}"
    );
    assert!(
        shader_artifacts["largest"]["bytes"]
            .as_u64()
            .is_some_and(|bytes| bytes > 0),
        "doctor should publish the largest active shader artifact size\nstdout:\n{stdout}"
    );
    assert!(
        matches!(
            shader_artifacts["size_guard"]["status"].as_str(),
            Some("enforced") | Some("disabled")
        ),
        "doctor should publish shader artifact size guard status\nstdout:\n{stdout}"
    );
    if shader_artifacts["size_guard"]["status"].as_str() == Some("enforced") {
        let max_artifact_bytes = shader_artifacts["largest"]["bytes"]
            .as_u64()
            .expect("largest artifact bytes checked above");
        let guard_max_bytes = shader_artifacts["size_guard"]["max_spv_bytes"]
            .as_u64()
            .expect("enforced size guard should publish a numeric cap");
        assert!(
            max_artifact_bytes <= guard_max_bytes,
            "doctor should show the active shader artifact cap covers the largest artifact\nstdout:\n{stdout}"
        );
    }
    let build_timeouts = &document["toolchain"]["build_timeouts"];
    assert_timeout_json_field(
        &build_timeouts["slangc_version_probe_ms"],
        "doctor slangc version timeout",
        &stdout,
    );
    assert_timeout_json_field(
        &build_timeouts["shader_compile_ms"],
        "doctor shader compile timeout",
        &stdout,
    );
    assert_eq!(
        build_timeouts["env"]["slangc_version_probe_ms"],
        "LANIUS_SLANGC_VERSION_TIMEOUT_MS"
    );
    assert_eq!(
        build_timeouts["env"]["shader_compile_ms"],
        "LANIUS_SHADER_COMPILE_TIMEOUT_MS"
    );
    assert!(
        build_timeouts["policy"]
            .as_str()
            .is_some_and(|policy| policy.contains("time-bounded")),
        "doctor should describe build-time Slang timeout policy\nstdout:\n{stdout}"
    );
    assert_eq!(document["diagnostics"]["cli_flag"], "--diagnostic-format");
    assert_eq!(document["diagnostics"]["default_format"], "text");
    assert_eq!(
        document["diagnostics"]["accepted_formats"]
            .as_array()
            .expect("doctor should publish accepted diagnostic formats")
            .iter()
            .map(|value| value
                .as_str()
                .expect("diagnostic format should be a string"))
            .collect::<Vec<_>>(),
        vec!["text", "json", "lsp-json"],
        "doctor should publish the diagnostic renderer contract\nstdout:\n{stdout}"
    );
    assert_eq!(
        document["diagnostics"]["registry_schema_version"],
        laniusc_compiler::compiler::DIAGNOSTIC_REGISTRY_SCHEMA_VERSION
    );
    assert_eq!(
        document["diagnostics"]["formats_schema_version"],
        laniusc_compiler::compiler::DIAGNOSTIC_OUTPUT_FORMATS_SCHEMA_VERSION
    );
    assert_eq!(document["diagnostics"]["lsp_source"], "laniusc");
    assert_eq!(document["diagnostics"]["lsp_position_encoding"], "utf-16");
    let lsp_error_data = &document["diagnostics"]["lsp_error_data"];
    assert_eq!(lsp_error_data["schema_name"], "laniusc.lsp.error-data");
    assert_eq!(lsp_error_data["schema_version"], 2);
    assert_eq!(lsp_error_data["transport"], "json-rpc-error-data");
    assert_eq!(lsp_error_data["diagnostic_field"], "diagnostic");
    assert_eq!(
        lsp_error_data["supported_methods_field"],
        "supported_methods"
    );
    assert_eq!(lsp_error_data["no_run_guards_field"], "no_run_guards");
    assert_eq!(
        lsp_error_data["json_rpc_error_codes"]["parse_error"],
        -32700
    );
    assert_eq!(
        lsp_error_data["json_rpc_error_codes"]["invalid_request"],
        -32600
    );
    assert_eq!(
        lsp_error_data["json_rpc_error_codes"]["method_not_found"],
        -32601
    );
    assert_eq!(
        lsp_error_data["json_rpc_error_codes"]["invalid_params"],
        -32602
    );
    assert_eq!(
        lsp_error_data["json_rpc_error_codes"]["internal_error"],
        -32603
    );
    assert_eq!(
        lsp_error_data["json_rpc_error_codes"]["server_not_initialized"],
        -32002
    );
    assert_eq!(
        lsp_error_data["diagnostic_codes"]["unsupported_method"],
        "LNC0028"
    );
    assert_eq!(
        lsp_error_data["diagnostic_codes"]["invalid_message"],
        "LNC0029"
    );
    assert_eq!(document["readiness"]["status"], "not-production-ready");
    assert_eq!(
        document["readiness"]["default_no_run_gate"],
        "tools/compiler_acceptance.sh --tier readiness --check-plan"
    );
    assert_eq!(
        document["readiness"]["default_no_run_gate_compiles_tests"],
        false
    );
    assert_eq!(
        document["readiness"]["default_no_run_gate_creates_gpu_device"],
        false
    );
    assert_eq!(
        document["readiness"]["default_no_run_gate_invokes_pareas"],
        false
    );
    let test_discipline = &document["readiness"]["test_discipline"];
    assert_eq!(
        test_discipline["schema_name"],
        "laniusc.readiness.test-discipline"
    );
    assert_eq!(test_discipline["schema_version"], 1);
    assert_eq!(
        test_discipline["inventory_gate"],
        "tools/compiler_acceptance.sh --tier readiness --check-plan"
    );
    assert_eq!(test_discipline["inventory_gate_compiles_tests"], false);
    assert_eq!(test_discipline["inventory_gate_executes_tests"], false);
    assert_eq!(test_discipline["named_filter_existence_check"], true);
    assert_eq!(
        test_discipline["duplicate_same_lane_references_rejected"],
        true
    );
    assert_eq!(test_discipline["rust_integration_test_audit"], true);
    assert_eq!(
        test_discipline["compiler_shader_product_source_inspection"],
        "rejected"
    );
    assert_eq!(
        test_discipline["source_scoped_evidence_policy"],
        "public-boundary-artifact-contract-execution-contract-or-measurement-scaffold-only"
    );
    assert_eq!(document["readiness"]["generated_scale_lane"], "opt-in");
    assert_eq!(document["readiness"]["pareas_lane"], "opt-in");
    assert_eq!(
        document["readiness"]["performance_claims"],
        "local-artifacts-required"
    );
    assert_eq!(
        document["readiness"]["paper_numbers"],
        "reference-only-not-local-performance-evidence"
    );
    let claim_requirements = document["readiness"]["claim_requirements"]
        .as_array()
        .expect("doctor should publish readiness claim requirements");
    for required in [
        "supported language slice evidence",
        "object/interface/partial-link artifacts",
        "claimable pass contracts",
        "local timing/readback/VRAM artifacts",
        "source-control provenance",
        "repeatability",
    ] {
        assert!(
            claim_requirements
                .iter()
                .any(|value| value.as_str() == Some(required)),
            "doctor readiness claim requirements should include {required:?}\nstdout:\n{stdout}"
        );
    }
    assert_eq!(document["pass_contracts"]["status"], "blocked");
    assert_eq!(
        document["pass_contracts"]["loop_policy"],
        "scale-claims-require-unbounded-pass-loops"
    );
    assert_eq!(document["pass_contracts"]["fallback_status"], "fail-closed");
    assert_eq!(document["pass_contracts"]["claim_status"], "blocked");
    assert_eq!(
        document["pass_contracts"]["paper_alignment_policy"],
        "paper-and-pareas-pass-shape-required"
    );
    assert_eq!(
        document["pass_contracts"]["audit_command"],
        "tools/shader_loop_audit.sh --summary-only"
    );
    assert_eq!(
        document["pass_contracts"]["paper_pass_blocker_gate"],
        "tools/shader_loop_audit.sh --summary-only --fail-on-paper-pass-blocker"
    );
    assert_eq!(
        document["pass_contracts"]["source_sized_symbolic_cap_gate"],
        "tools/shader_loop_audit.sh --summary-only --fail-on-source-sized-symbolic-cap"
    );
    assert_eq!(
        document["pass_contracts"]["audit_executed_by_doctor"], false,
        "doctor should publish pass-contract audit metadata without running the audit\nstdout:\n{stdout}"
    );
    assert_eq!(
        document["pass_contracts"]["claim_boundary"],
        "metadata-only-no-run-not-performance-evidence"
    );
    let expected_gpu_primitives = document["pass_contracts"]["expected_gpu_primitives"]
        .as_array()
        .expect("doctor should publish the paper/Pareas primitive contract");
    for primitive in [
        "record-publication",
        "prefix-scan",
        "segmented-scan",
        "sort-join",
        "scatter",
        "reduction",
    ] {
        assert!(
            expected_gpu_primitives
                .iter()
                .any(|value| value.as_str() == Some(primitive)),
            "doctor should publish expected GPU primitive {primitive:?}\nstdout:\n{stdout}"
        );
    }
    assert_eq!(
        document["pass_contracts"]["source_sized_symbolic_caps"],
        "claim-blockers-until-justified-or-rewritten"
    );
    assert_eq!(document["language_slice"]["edition"], "unstable-alpha");
    assert_eq!(
        document["language_slice"]["status"],
        "bounded-unstable-alpha"
    );
    assert_eq!(
        document["language_slice"]["inventory_path"],
        "docs/language_slice_unstable_alpha.tsv"
    );
    assert_eq!(
        document["language_slice"]["inventory_gate"],
        "tools/compiler_acceptance.sh --tier readiness --check-plan"
    );
    assert_eq!(
        document["language_slice"]["inventory_checked_by_doctor"], false,
        "doctor should point at the slice inventory without executing the gate\nstdout:\n{stdout}"
    );
    assert_eq!(
        document["language_slice"]["production_release_claim"],
        false
    );
    assert_eq!(
        document["language_slice"]["supported_statuses"]
            .as_array()
            .expect("doctor should publish supported language-slice statuses")
            .iter()
            .map(|value| value
                .as_str()
                .expect("language-slice status should be a string"))
            .collect::<Vec<_>>(),
        vec!["supported", "bounded"]
    );
    assert_eq!(
        document["language_slice"]["non_support_statuses"]
            .as_array()
            .expect("doctor should publish non-support language-slice statuses")
            .iter()
            .map(|value| value
                .as_str()
                .expect("language-slice status should be a string"))
            .collect::<Vec<_>>(),
        vec!["planned", "unsupported"]
    );
    let evidence_contracts = document["language_slice"]["evidence_contracts"]
        .as_array()
        .expect("doctor should publish accepted evidence contract names");
    for expected_contract in [
        "public-boundary",
        "artifact-contract",
        "record-invariant",
        "semantic-contract",
        "execution-contract",
        "fail-closed-diagnostic",
        "measurement-scaffold",
    ] {
        assert!(
            evidence_contracts
                .iter()
                .any(|value| value.as_str() == Some(expected_contract)),
            "doctor should publish evidence contract {expected_contract:?}\nstdout:\n{stdout}"
        );
    }
    assert!(
        document["language_slice"]["policy"]
            .as_str()
            .is_some_and(|policy| policy.contains("behavior-facing evidence")
                && policy.contains("explicit non-support")),
        "doctor should describe how to read supported and unsupported slice rows\nstdout:\n{stdout}"
    );
    assert_eq!(document["stdlib"]["status"], "explicit-root-required");
    assert_eq!(document["stdlib"]["cli_flag"], "--stdlib-root");
    assert_eq!(document["stdlib"]["suggested_root"], "stdlib");
    assert_eq!(document["stdlib"]["auto_imported"], false);
    assert_eq!(document["stdlib"]["source_rewrite"], false);
    assert_eq!(
        document["stdlib"]["runtime_bound_status"],
        "known-unbound-contracts"
    );
    assert_eq!(document["stdlib"]["executable_host_apis"], false);
    assert_eq!(
        document["stdlib"]["runtime_boundary_diagnostic_code"],
        "LNC0038"
    );
    assert_eq!(
        document["stdlib"]["runtime_boundary_explain_command"],
        "laniusc diagnostics explain LNC0038"
    );
    assert_eq!(
        document["stdlib"]["runtime_service_boundary_count"],
        laniusc_compiler::compiler::RUNTIME_SERVICE_BOUNDARY_DIAGNOSTICS.len()
    );
    assert_eq!(
        document["stdlib"]["runtime_bound_api_count"],
        laniusc_compiler::compiler::RUNTIME_BOUND_API_DIAGNOSTICS.len()
    );
    assert_eq!(
        document["stdlib"]["runtime_boundary_detail"],
        "use diagnostics explain LNC0038, diagnostics runtime-apis, or diagnostics runtime-services for row-level runtime boundary metadata"
    );
    assert!(
        document["stdlib"]["runtime_service_boundaries"].is_null(),
        "doctor should stay a compact install report; row-level service metadata belongs to diagnostics commands\nstdout:\n{stdout}"
    );
    assert!(
        document["stdlib"]["runtime_bound_apis"].is_null(),
        "doctor should stay a compact install report; row-level API metadata belongs to diagnostics commands\nstdout:\n{stdout}"
    );
    let stdlib_layers = document["stdlib"]["layers"]
        .as_array()
        .expect("doctor should publish stdlib layer contract rows");
    assert_eq!(
        stdlib_layers
            .iter()
            .map(|layer| layer["name"]
                .as_str()
                .expect("stdlib layer name should be a string"))
            .collect::<Vec<_>>(),
        vec!["core", "alloc", "std", "test"],
        "doctor should publish the stdlib layer boundary\nstdout:\n{stdout}"
    );
    assert!(stdlib_layers.iter().any(|layer| {
        layer["name"] == "core"
            && layer["current_status"] == "source-seed"
            && layer["host_runtime_required"] == false
            && layer["auto_imported"] == false
    }));
    assert!(stdlib_layers.iter().any(|layer| {
        layer["name"] == "std"
            && layer["current_status"] == "runtime-contract"
            && layer["host_runtime_required"] == true
            && layer["auto_imported"] == false
    }));
    assert_eq!(
        document["no_run_guards"]["source_compilation"], false,
        "doctor should not compile source"
    );
    assert_eq!(
        document["no_run_guards"]["language_slice_inventory_validation"], false,
        "doctor should not validate the language-slice inventory"
    );
    assert_eq!(
        document["no_run_guards"]["stdlib_source_scanning"], false,
        "doctor should not scan stdlib sources"
    );
    assert_eq!(
        document["no_run_guards"]["shader_loop_audit_execution"], false,
        "doctor should not run shader loop audits"
    );
    assert_eq!(
        document["no_run_guards"]["target_codegen"], false,
        "doctor should not run target codegen"
    );
    assert_eq!(
        document["no_run_guards"]["gpu_device_creation"], false,
        "doctor should not create a GPU device"
    );
    assert_eq!(
        document["no_run_guards"]["readiness_gate_execution"], false,
        "doctor should not execute readiness gates"
    );
    assert_eq!(
        document["no_run_guards"]["pareas_invocation"], false,
        "doctor should not invoke Pareas"
    );
    assert_eq!(
        document["no_run_guards"]["generated_workloads"], false,
        "doctor should not run generated workloads"
    );
}

#[test]
fn cli_doctor_honors_slangc_environment_override_without_compiling_source() {
    let missing_slangc = "/definitely/not/a/lanius-test-slangc";
    let mut command = Command::new(laniusc_bin());
    command.arg("doctor").env("SLANGC", missing_slangc);

    let output = common::command_output_with_timeout("laniusc doctor with SLANGC", &mut command);
    common::assert_command_success("laniusc doctor with SLANGC", &output);

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.is_empty(),
        "doctor should keep override status in JSON, not stderr\nstderr:\n{stderr}"
    );
    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("doctor output should be JSON");
    assert_eq!(document["status"], "action-required");
    assert_eq!(
        document["toolchain"]["slangc"]["source"], "SLANGC",
        "doctor should identify the configured Slang source\nstdout:\n{stdout}"
    );
    assert_eq!(
        document["toolchain"]["slangc"]["path"], missing_slangc,
        "doctor should check the configured Slang path\nstdout:\n{stdout}"
    );
    assert_eq!(
        document["toolchain"]["slangc"]["status"], "missing",
        "missing configured Slang should be an actionable toolchain status\nstdout:\n{stdout}"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["readiness_gate_execution"], false);
    assert_eq!(
        document["no_run_guards"]["shader_loop_audit_execution"],
        false
    );
    assert_eq!(document["no_run_guards"]["pareas_invocation"], false);
    assert_eq!(document["no_run_guards"]["generated_workloads"], false);
}

#[test]
fn cli_doctor_bounds_slangc_version_probe_without_compiling_source() {
    let fake_slangc = create_stalling_slangc_script();
    let mut command = Command::new(laniusc_bin());
    command.arg("doctor").env("SLANGC", &fake_slangc);

    let started = Instant::now();
    let output =
        common::command_output_with_timeout("laniusc doctor with stalled SLANGC", &mut command);
    let elapsed = started.elapsed();
    let _ = fs::remove_file(&fake_slangc);
    common::assert_command_success("laniusc doctor with stalled SLANGC", &output);

    assert!(
        elapsed < Duration::from_secs(10),
        "doctor should not wait for a stalled Slang process to finish\nelapsed: {elapsed:?}"
    );
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.is_empty(),
        "doctor should keep Slang probe timeout status in JSON, not stderr\nstderr:\n{stderr}"
    );
    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("doctor output should be JSON");
    assert_eq!(document["status"], "action-required");
    assert_eq!(document["toolchain"]["slangc"]["source"], "SLANGC");
    assert_eq!(
        document["toolchain"]["slangc"]["path"].as_str(),
        fake_slangc.to_str()
    );
    assert_eq!(
        document["toolchain"]["slangc"]["status"], "error",
        "timeout is an actionable Slang toolchain error\nstdout:\n{stdout}"
    );
    assert_eq!(document["toolchain"]["slangc"]["error_kind"], "timeout");
    assert_eq!(document["toolchain"]["slangc"]["arg"], "-version");
    assert!(
        document["toolchain"]["slangc"]["timeout_ms"]
            .as_u64()
            .is_some_and(|timeout_ms| timeout_ms > 0),
        "doctor should publish the Slang probe timeout budget\nstdout:\n{stdout}"
    );
    assert_eq!(document["no_run_guards"]["source_compilation"], false);
    assert_eq!(document["no_run_guards"]["target_codegen"], false);
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["readiness_gate_execution"], false);
    assert_eq!(
        document["no_run_guards"]["shader_loop_audit_execution"],
        false
    );
    assert_eq!(document["no_run_guards"]["pareas_invocation"], false);
    assert_eq!(document["no_run_guards"]["generated_workloads"], false);
}

#[test]
fn cli_accepts_explicit_current_language_edition() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--edition")
        .arg("unstable-alpha")
        .env("LANIUS_COMPILER_PROCESS_TEST_TIMEOUT_MS", "60000");

    let output =
        common::command_output_with_timeout("laniusc --edition unstable-alpha", &mut command);
    common::assert_command_success("laniusc --edition unstable-alpha", &output);
    assert!(
        output.stdout.starts_with(b"\x7fELF"),
        "default compile should emit x86_64 ELF bytes for the accepted edition\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn cli_rejects_unsupported_language_edition_before_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--edition=future-stable")
        .arg("/definitely/not/a/source/file.lani");

    let output =
        common::command_output_with_timeout("laniusc unsupported language edition", &mut command);
    assert!(
        !output.status.success(),
        "unsupported edition should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("unsupported language edition"));
    assert!(stderr.contains("future-stable"));
    assert!(stderr.contains("unstable-alpha"));
    assert!(
        !stderr.contains("/definitely/not/a/source/file.lani"),
        "edition validation should happen before source loading\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_rejects_unsupported_target_triple_before_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--target=riscv64gc-unknown-linux-gnu")
        .arg("/definitely/not/a/source/file.lani");

    let output = common::command_output_with_timeout("laniusc unsupported target", &mut command);
    assert!(
        !output.status.success(),
        "unsupported target should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("unsupported target triple"));
    assert!(stderr.contains("riscv64gc-unknown-linux-gnu"));
    assert!(stderr.contains("wasm32-unknown-unknown"));
    assert!(
        !stderr.contains("/definitely/not/a/source/file.lani"),
        "target validation should happen before source loading\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_rejects_emit_target_mismatch_before_compiling_source() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--emit=wasm")
        .arg("--target=x86_64-unknown-linux-gnu")
        .arg("/definitely/not/a/source/file.lani");

    let output =
        common::command_output_with_timeout("laniusc mismatched emit and target", &mut command);
    assert!(
        !output.status.success(),
        "emit/target mismatch should fail\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("requires --emit x86_64"));
    assert!(stderr.contains("requested --emit wasm"));
    assert!(
        !stderr.contains("/definitely/not/a/source/file.lani"),
        "target validation should happen before source loading\nstderr:\n{stderr}"
    );
}

fn create_stalling_slangc_script() -> PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("system clock should be after Unix epoch")
        .as_nanos();
    let dir = env::temp_dir().join(format!(
        "laniusc-doctor-stalled-slangc-{}-{nonce}",
        std::process::id()
    ));
    fs::create_dir_all(&dir).expect("create fake Slang directory");
    let script = dir.join("slangc");
    fs::write(&script, "#!/bin/sh\nexec sleep 20\n").expect("write fake Slang script");
    let mut permissions = fs::metadata(&script)
        .expect("stat fake Slang script")
        .permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&script, permissions).expect("make fake Slang script executable");
    script
}

fn parse_version_fields<'a>(
    lines: impl Iterator<Item = &'a str>,
    stdout: &str,
) -> BTreeMap<String, String> {
    let mut fields = BTreeMap::new();
    for line in lines {
        let (key, value) = line
            .split_once(':')
            .unwrap_or_else(|| panic!("version field should use `key: value`: {line:?}"));
        let key = key.trim().to_string();
        let value = value.trim().to_string();
        assert!(
            fields.insert(key.clone(), value).is_none(),
            "--version should not repeat field {key}\nstdout:\n{stdout}"
        );
    }
    fields
}

fn assert_field_contains(
    fields: &BTreeMap<String, String>,
    field: &str,
    expected: &str,
    stdout: &str,
) {
    let value = fields
        .get(field)
        .unwrap_or_else(|| panic!("--version should report {field}\nstdout:\n{stdout}"));
    assert!(
        value.contains(expected),
        "--version field {field} should contain {expected:?}\nstdout:\n{stdout}"
    );
}

fn assert_timeout_field(
    fields: &BTreeMap<String, String>,
    field: &str,
    command: &str,
    stdout: &str,
) {
    let value = fields
        .get(field)
        .unwrap_or_else(|| panic!("{command} should report {field}\nstdout:\n{stdout}"));
    assert!(
        value == "disabled" || value.parse::<u64>().is_ok_and(|timeout| timeout > 0),
        "{command} field {field} should be a positive millisecond budget or disabled\nstdout:\n{stdout}"
    );
}

fn assert_timeout_json_field(value: &serde_json::Value, label: &str, stdout: &str) {
    assert!(
        value == "disabled" || value.as_u64().is_some_and(|timeout| timeout > 0),
        "{label} should be a positive millisecond budget or disabled\nstdout:\n{stdout}"
    );
}
