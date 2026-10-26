#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/run_group.lani");
        let stdlib = root().join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("run-group", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("run-group: {error}"));
        let artifact = common::TempArtifact::new("run_group", "executable", None);
        artifact.write_bytes(bytes);
        fs::set_permissions(artifact.path(), fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str) {
    let fixtures = root().join("tests/fixtures/stdlib_foundation/run_group");
    let output = common::process_output_with_timeout(
        format!("run-group {mode}"),
        Command::new("python3")
            .arg(fixtures.join("oracle.py"))
            .arg(cli().path())
            .arg(fixtures.join("peer.py"))
            .arg(mode),
        Duration::from_secs(60),
    );
    assert_eq!(output.status.code(), Some(0), "{mode}: {output:?}");
    assert!(output.stderr.is_empty(), "{mode}: {output:?}");
    let receipt = String::from_utf8(output.stdout).unwrap();
    assert!(
        receipt.contains(&format!("run-group {mode}:")) && receipt.contains("exact owner ledgers"),
        "{receipt}"
    );
    eprint!("{receipt}");
}

#[test]
fn real_supervisor_preserves_command_arguments_environment_and_ordinary_status() {
    oracle("normal");
}

#[test]
fn timeout_escalation_retains_leader_anchor_and_discloses_group_escape_limits() {
    oracle("groups");
}

#[test]
fn exact_host_faults_interruptions_and_monitor_budget_keep_explicit_cleanup() {
    oracle("faults");
}

#[test]
fn unreaped_and_lost_child_authority_never_becomes_a_post_reap_signal() {
    oracle("ownership");
}

#[test]
fn all_reached_pre_spawn_allocation_failures_release_owners_without_starting_child() {
    oracle("allocations");
}
