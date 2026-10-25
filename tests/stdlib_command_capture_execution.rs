#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::Path, process::Command};
fn executable(name: &str, source: &str) -> common::TempArtifact {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(source);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let artifact = common::TempArtifact::new("laniusc_command_capture", name, None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}
#[test]
fn concrete_three_pipe_admission_and_owner_progress_contracts_execute() {
    for name in ["command_capture_admission", "command_capture_contracts"] {
        let artifact = executable(
            name,
            &format!("tests/fixtures/stdlib_foundation/{name}.lani"),
        );
        let output = Command::new("timeout")
            .args(["--kill-after=1s", "8s"])
            .arg(artifact.path())
            .output()
            .expect("run bounded native capture contracts");
        assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
    }
}
#[test]
fn real_capture_cli_concurrency_and_independent_resource_fault_models_execute() {
    let cli = executable(
        "capture_command",
        "sample_programs/library/capture_command.lani",
    );
    let faults = executable(
        "command_capture_faults",
        "tests/fixtures/stdlib_foundation/command_capture_faults.lani",
    );
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let output = Command::new("timeout")
        .args(["--kill-after=1s", "40s", "python3"])
        .arg(root.join("tests/fixtures/stdlib_foundation/command_capture_oracle.py"))
        .args([cli.path(), faults.path()])
        .output()
        .expect("run bounded independent capture models");
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        String::from_utf8_lossy(&output.stdout).contains("ledgers balanced"),
        "{output:?}"
    );
    assert!(output.stderr.is_empty(), "{output:?}");
}
