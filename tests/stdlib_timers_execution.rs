//! timerfd timers: one-shot, periodic, absolute and alarm clocks; the timer-ticks program.
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
    let artifact = common::TempArtifact::new("timers", label, None);
    artifact.write_bytes(bytes);
    std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    artifact
}
fn timer_ticks() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("sample_programs/library/timer_ticks.lani", "timer_ticks"))
}
fn oracle(mode: &str, cases: usize) {
    let output = common::process_output_with_timeout(
        format!("timer-ticks {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_timers/oracle.py"))
            .arg(mode)
            .arg(timer_ticks().path()),
        Duration::from_secs(60),
    );
    common::assert_command_success(format!("timer-ticks {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        String::from_utf8(output.stdout).unwrap(),
        format!("timer-ticks-{mode} cases={cases}\n")
    );
}

#[test]
fn timers_contracts_execute() {
    let exe = executable("tests/fixtures/stdlib_timers/contracts.lani", "contracts");
    let output = common::process_output_with_timeout(
        "timer contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success("timer contracts", &output);
    assert!(output.stdout.is_empty() && output.stderr.is_empty(), "{output:?}");
}
#[test]
fn timer_ticks_cli_and_alarm_permissions_match_host() {
    oracle("cli", 19);
}
#[test]
fn timer_ticks_expiration_counts_match_elapsed_time_and_overruns() {
    oracle("ticks", 138);
}
