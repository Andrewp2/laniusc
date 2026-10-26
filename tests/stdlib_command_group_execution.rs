#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
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
fn fixture(name: &str) -> common::TempArtifact {
    let entry = root()
        .join("tests/fixtures/stdlib_foundation/command_group")
        .join(name);
    let stdlib = root().join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("command group", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("command_group", name, None);
    file.write_bytes(bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn probe() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| fixture("probe.lani"))
}
fn failure() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| fixture("failure.lani"))
}
fn confirm() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| fixture("confirm.lani"))
}
fn group(name: &str) {
    let base = root().join("tests/fixtures/stdlib_foundation/command_group");
    let probe_path = if name == "faults" {
        PathBuf::from("-")
    } else {
        probe().path().to_path_buf()
    };
    let failure_path = if name == "faults" {
        failure().path().to_path_buf()
    } else {
        PathBuf::from("-")
    };
    let confirm_path = if name == "faults" {
        confirm().path().to_path_buf()
    } else {
        PathBuf::from("-")
    };
    let mut command = Command::new("python3");
    command
        .arg(base.join("oracle.py"))
        .arg(probe_path)
        .arg(failure_path)
        .arg(confirm_path)
        .arg(base.join("peer.py"))
        .arg(name);
    let output = common::process_output_with_timeout(
        "command group oracle",
        &mut command,
        Duration::from_secs(50),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert!(
        String::from_utf8_lossy(&output.stdout).contains("owner ledgers checked"),
        "{output:?}"
    );
}
#[test]
fn inherited_and_new_groups_preserve_session_and_parent_isolation() {
    group("membership");
}
#[test]
fn group_signals_reach_grandchildren_and_cancel_an_escaped_leader() {
    group("signals");
}
#[test]
fn observation_reap_and_echild_preserve_or_revoke_the_exact_authority() {
    group("authority");
}
#[test]
fn capture_retains_terminal_leader_anchor_until_drain_or_failure() {
    group("capture");
}
#[test]
fn setup_packets_uncertainty_and_syscall_resource_faults_retain_cleanup_authority() {
    group("faults");
}
