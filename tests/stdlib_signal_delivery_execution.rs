//! Signal masks, signalfd delivery, handled sets and resource limits; the supervise program.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
use crate::common;
use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn executable(path: &'static str, label: &str) -> common::TempArtifact {
    let entry = root().join(path);
    let stdlib = root().join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let artifact = common::TempArtifact::new("signals", label, None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}
fn supervise() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("sample_programs/library/supervise.lani", "supervise"))
}
fn oracle(mode: &str, cases: usize) {
    let output = common::process_output_with_timeout(
        format!("supervise {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_signals/oracle.py"))
            .arg(mode)
            .arg(supervise().path()),
        Duration::from_secs(60),
    );
    common::assert_command_success(format!("supervise {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        format!("supervise-{mode} cases={cases}\n")
    );
}

#[test]
fn signal_and_limit_contracts_execute() {
    let exe = executable("tests/fixtures/stdlib_signals/contracts.lani", "contracts");
    let output = common::process_output_with_timeout(
        "signal contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success("signal contracts", &output);
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}");
}
#[test]
fn supervise_cli_and_child_environment_match_host() {
    oracle("cli", 50);
}
#[test]
fn supervise_restarts_with_backoff_and_forwards_signals() {
    oracle("supervise", 97);
}
