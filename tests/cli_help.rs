mod common;

use std::{env, path::PathBuf, process::Command};

fn laniusc_bin() -> PathBuf {
    option_env!("CARGO_BIN_EXE_laniusc")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("target/debug/laniusc"))
}

#[test]
fn cli_top_level_help_short_circuits_compile_arguments() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("--help")
        .arg("--emit=not-a-real-target")
        .arg("/definitely/not/a/source/file.lani");

    let output = common::command_output_with_timeout("laniusc --help", &mut command);
    common::assert_command_success("laniusc --help", &output);

    assert!(
        output.stdout.is_empty(),
        "top-level help should use stderr like the rest of the CLI\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("Usage: laniusc [-h|--help] [-V|--version]"),
        "top-level help should print the main usage line with supported help/version shortcuts\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("Usage: laniusc check"),
        "top-level help should list the check command\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("Usage: laniusc daemon --stdio")
            && stderr.contains("keeps one GPU compiler resident"),
        "top-level help should expose the resident compiler daemon\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains(
            "Usage: laniusc doctor [--skip-slangc-probe] [--diagnostic-format text|json|lsp-json]"
        ),
        "top-level help should list the doctor command\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("doctor prints a compact no-run JSON toolchain/readiness report"),
        "top-level help should describe doctor as a no-run tooling report\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("metadata command discovery"),
        "top-level help should direct wrappers toward machine-readable metadata command discovery\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("guards proving it did not compile source"),
        "top-level help should publish the doctor no-run guard contract\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("error[") && !stderr.contains("laniusc:"),
        "--help should not validate later compile arguments or emit diagnostics\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_short_help_matches_long_help_and_documents_short_flags() {
    let mut long_command = Command::new(laniusc_bin());
    long_command
        .arg("--help")
        .arg("--emit=not-a-real-target")
        .arg("/definitely/not/a/source/file.lani");
    let long_output = common::command_output_with_timeout("laniusc --help", &mut long_command);
    common::assert_command_success("laniusc --help", &long_output);

    let mut short_command = Command::new(laniusc_bin());
    short_command
        .arg("-h")
        .arg("--emit=not-a-real-target")
        .arg("/definitely/not/a/source/file.lani");
    let short_output = common::command_output_with_timeout("laniusc -h", &mut short_command);
    common::assert_command_success("laniusc -h", &short_output);

    assert_eq!(
        short_output.stderr, long_output.stderr,
        "-h should expose the same help contract as --help"
    );
    assert!(
        short_output.stdout.is_empty(),
        "-h should write help to stderr like --help\nstdout:\n{}",
        String::from_utf8_lossy(&short_output.stdout)
    );
    let stderr = String::from_utf8_lossy(&short_output.stderr);
    assert!(
        stderr.contains("[-h|--help] [-V|--version]"),
        "top-level help should document the accepted short help/version flags\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("-h/--help prints this help"),
        "top-level help should describe the short help flag\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("-V/--version prints compiler"),
        "top-level help should describe the short version flag\nstderr:\n{stderr}"
    );
    assert!(
        stderr.lines().any(|line| {
            line.contains("-V/--version") && line.contains("release/distribution status")
        }),
        "top-level help should tell users that --version publishes the release/distribution boundary\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("error[") && !stderr.contains("laniusc:"),
        "-h should not validate later compile arguments or emit diagnostics\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_diagnostics_help_includes_copyable_metadata_examples() {
    let mut command = Command::new(laniusc_bin());
    command.arg("diagnostics").arg("--help");

    let output = common::command_output_with_timeout("laniusc diagnostics --help", &mut command);
    common::assert_command_success("laniusc diagnostics --help", &output);

    assert!(
        output.stdout.is_empty(),
        "diagnostics help should use stderr like other help surfaces\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("laniusc diagnostics code LNC0018 looks up one stable diagnostic code"),
        "diagnostics help should include a copyable focused code lookup example\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains(
            "laniusc diagnostics code 'error[LNC0018]: unsupported CLI option value' accepts a copied diagnostic heading"
        ),
        "diagnostics help should show that copied diagnostic headings are valid selectors\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains(
            "laniusc diagnostics formats lists JSON and LSP diagnostic payload contracts"
        ),
        "diagnostics help should point wrappers at renderer metadata\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("laniusc diagnostics formatter lists formatter/editor-wrapper policy"),
        "diagnostics help should point wrappers at formatter policy metadata\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains(
            "laniusc diagnostics version-policy lists machine-readable command discovery"
        ),
        "diagnostics help should point wrappers at metadata command discovery\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_diagnostics_code_help_short_circuits_selector_lookup() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("code")
        .arg("--help")
        .arg("--diagnostic-format=json")
        .arg("--not-a-selector");

    let output =
        common::command_output_with_timeout("laniusc diagnostics code --help", &mut command);
    common::assert_command_success("laniusc diagnostics code --help", &output);

    assert!(
        output.stdout.is_empty(),
        "focused diagnostics code help should use stderr like other help surfaces\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains(
            "Usage: laniusc diagnostics [--diagnostic-format text|json|lsp-json] code CODE"
        ),
        "focused diagnostics code help should print the exact lookup usage\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("Accepted CODE selectors: LNC0018, lnc0018"),
        "focused diagnostics code help should list accepted selector shapes\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("laniusc diagnostics code 'error[LNC0018]: unsupported CLI option value'"),
        "focused diagnostics code help should include a copied-heading example\nstderr:\n{stderr}"
    );
    assert!(
        stderr.contains("Use laniusc diagnostics codes for the compact code index"),
        "focused diagnostics code help should point at bulk discovery\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("\"schema_name\"") && !stderr.contains("unknown CLI option"),
        "focused diagnostics code help should not perform a JSON lookup or validate trailing lookup arguments\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_diagnostics_explain_help_short_circuits_selector_lookup() {
    let mut command = Command::new(laniusc_bin());
    command
        .arg("diagnostics")
        .arg("explain")
        .arg("--help")
        .arg("--diagnostic-format=json")
        .arg("--not-a-selector");

    let output =
        common::command_output_with_timeout("laniusc diagnostics explain --help", &mut command);
    common::assert_command_success("laniusc diagnostics explain --help", &output);

    assert!(
        output.stdout.is_empty(),
        "focused diagnostics explain help should use stderr like other help surfaces\nstdout:\n{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.lines().any(|line| {
            line.contains("diagnostics") && line.contains("explain") && line.contains("CODE")
        }),
        "focused diagnostics explain help should advertise the code-selector usage\nstderr:\n{stderr}"
    );
    assert!(
        stderr.lines().any(|line| line.contains("CODE selectors")),
        "focused diagnostics explain help should document accepted selector shapes\nstderr:\n{stderr}"
    );
    assert!(
        stderr
            .lines()
            .any(|line| line.contains("known:false") && line.contains("unknown code")),
        "focused diagnostics explain help should describe unknown-code behavior\nstderr:\n{stderr}"
    );
    assert!(
        !stderr.contains("\"schema_name\"") && !stderr.contains("unknown CLI option"),
        "focused diagnostics explain help should not perform a JSON lookup or validate trailing lookup arguments\nstderr:\n{stderr}"
    );
}

#[test]
fn cli_doctor_can_skip_slangc_probe_for_metadata_only_wrappers() {
    let missing_slangc = "/definitely/not/a/lanius-test-slangc";
    let mut command = Command::new(laniusc_bin());
    command
        .arg("doctor")
        .arg("--skip-slangc-probe")
        .env("SLANGC", missing_slangc);

    let output =
        common::command_output_with_timeout("laniusc doctor --skip-slangc-probe", &mut command);
    common::assert_command_success("laniusc doctor --skip-slangc-probe", &output);

    assert!(
        output.stderr.is_empty(),
        "doctor skip-probe success should not print diagnostics\nstderr:\n{}",
        String::from_utf8_lossy(&output.stderr)
    );

    let stdout = String::from_utf8_lossy(&output.stdout);
    let document: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("doctor output should be JSON");
    assert_eq!(
        document["status"], "not-checked",
        "doctor should not claim local Slang readiness when the probe is skipped\nstdout:\n{stdout}"
    );
    assert_eq!(
        document["toolchain"]["slangc"]["status"], "skipped",
        "doctor should publish skipped Slang probe status\nstdout:\n{stdout}"
    );
    assert_eq!(
        document["toolchain"]["slangc"]["source"], "SLANGC",
        "doctor should still report which Slang selector would have been used\nstdout:\n{stdout}"
    );
    assert_eq!(
        document["toolchain"]["slangc"]["path"], missing_slangc,
        "doctor should still report the configured Slang path\nstdout:\n{stdout}"
    );
    assert_eq!(
        document["toolchain"]["slangc"]["probe_attempted"], false,
        "doctor should expose that it avoided the runtime Slang subprocess\nstdout:\n{stdout}"
    );
    assert_eq!(
        document["no_run_guards"]["slangc_probe"], false,
        "doctor no-run guards should reflect the skipped Slang probe\nstdout:\n{stdout}"
    );
    assert_eq!(
        document["no_run_guards"]["source_compilation"], false,
        "skip-probe doctor should still be a no-source-compilation command\nstdout:\n{stdout}"
    );
}
