//! wait4 and getrusage resource usage in std::command; the child-usage program.
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
    let artifact = common::TempArtifact::new("child_usage", label, None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}
fn child_usage() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("sample_programs/library/child_usage.lani", "child_usage"))
}
fn oracle(mode: &str, cases: usize) {
    let output = common::process_output_with_timeout(
        format!("child-usage {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_child_usage/oracle.py"))
            .arg(mode)
            .arg(child_usage().path()),
        Duration::from_secs(60),
    );
    common::assert_command_success(format!("child-usage {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        format!("child-usage-{mode} cases={cases}\n")
    );
}

#[test]
fn child_usage_contracts_execute() {
    let exe = executable("tests/fixtures/stdlib_child_usage/contracts.lani", "contracts");
    let output = common::process_output_with_timeout(
        "child usage contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success("child usage contracts", &output);
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}");
}
#[test]
fn child_usage_cli_statuses_and_stream_passthrough_match_host() {
    oracle("cli", 39);
}
#[test]
fn child_usage_cpu_memory_switches_and_block_io_match_host_rusage() {
    oracle("usage", 42);
}
