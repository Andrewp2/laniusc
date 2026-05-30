mod common;

use std::{collections::BTreeMap, path::PathBuf, process::Command};

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
        Some("wasm, x86_64"),
        "--version should list the accepted emit targets\nstdout:\n{stdout}"
    );
    assert_eq!(
        fields.get("target-triples").map(String::as_str),
        Some("wasm32-unknown-unknown, x86_64-unknown-linux-gnu"),
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
        fields.get("lsp-capabilities-schema").map(String::as_str),
        Some("4"),
        "--version should publish the LSP capabilities schema version\nstdout:\n{stdout}"
    );
    assert_eq!(
        fields.get("lsp-experimental-schema").map(String::as_str),
        Some("2"),
        "--version should publish the LSP experimental extension schema version\nstdout:\n{stdout}"
    );
    for field in ["slangc", "wgpu", "build-profile", "shader-artifact-digest"] {
        let value = fields
            .get(field)
            .unwrap_or_else(|| panic!("--version should report {field}\nstdout:\n{stdout}"));
        assert!(
            !value.trim().is_empty() && value != "unknown",
            "--version field {field} should be populated for a built binary\nstdout:\n{stdout}"
        );
    }
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
    assert_eq!(document["schema_version"], 3);
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
        vec!["wasm", "x86_64"]
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
    assert_eq!(document["diagnostics"]["registry_schema_version"], 5);
    assert_eq!(document["diagnostics"]["formats_schema_version"], 5);
    assert_eq!(document["diagnostics"]["lsp_source"], "laniusc");
    assert_eq!(document["diagnostics"]["lsp_position_encoding"], "utf-16");
    assert_eq!(
        document["no_run_guards"]["source_compilation"], false,
        "doctor should not compile source"
    );
    assert_eq!(
        document["no_run_guards"]["gpu_device_creation"], false,
        "doctor should not create a GPU device"
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
    assert_eq!(document["no_run_guards"]["gpu_device_creation"], false);
    assert_eq!(document["no_run_guards"]["pareas_invocation"], false);
    assert_eq!(document["no_run_guards"]["generated_workloads"], false);
}

#[test]
fn cli_accepts_explicit_current_language_edition() {
    let mut command = Command::new(laniusc_bin());
    command.arg("--edition").arg("unstable-alpha");

    let output =
        common::command_output_with_timeout("laniusc --edition unstable-alpha", &mut command);
    common::assert_command_success("laniusc --edition unstable-alpha", &output);
    assert!(
        output.stdout.starts_with(b"\0asm"),
        "default compile should still emit Wasm bytes for the accepted edition\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}

#[test]
fn cli_accepts_explicit_supported_target_triple() {
    let mut command = Command::new(laniusc_bin());
    command.arg("--target").arg("wasm32-unknown-unknown");

    let output = common::command_output_with_timeout(
        "laniusc --target wasm32-unknown-unknown",
        &mut command,
    );
    common::assert_command_success("laniusc --target wasm32-unknown-unknown", &output);
    assert!(
        output.stdout.starts_with(b"\0asm"),
        "default compile should still emit Wasm bytes for the accepted target triple\nstdout:\n{}\nstderr:\n{}",
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
