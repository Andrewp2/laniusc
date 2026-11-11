//! Named Linux clocks, CPU clocks, absolute waits and the time-command program.
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
    let artifact = common::TempArtifact::new("host_clocks", label, None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}
fn time_command() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("sample_programs/library/time_command.lani", "time_command"))
}
fn oracle(mode: &str, cases: usize) {
    let output = common::process_output_with_timeout(
        format!("time-command {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_host_clocks/oracle.py"))
            .arg(mode)
            .arg(time_command().path()),
        Duration::from_secs(60),
    );
    common::assert_command_success(format!("time-command {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        format!("time-command-{mode} cases={cases}\n")
    );
}

#[test]
fn named_clock_ids_kinds_cpu_clocks_and_absolute_waits_execute() {
    let exe = executable("tests/fixtures/stdlib_host_clocks/contracts.lani", "contracts");
    let output = common::process_output_with_timeout(
        "host clock contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success("host clock contracts", &output);
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}");
}
#[test]
fn time_command_cli_statuses_and_stream_passthrough_match_host() {
    oracle("cli", 50);
}
#[test]
fn time_command_child_cpu_and_elapsed_times_match_host_accounting() {
    oracle("timing", 21);
}
#[test]
fn time_command_clock_table_matches_host_resolutions_and_readings() {
    oracle("clocks", 48);
}
