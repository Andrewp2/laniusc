//! Actual replacement-sink application with displaced-owner models and strict source traces.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]

mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn executable() -> &'static common::TempArtifact {
    static FILE: OnceLock<common::TempArtifact> = OnceLock::new();
    FILE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/latest_values.lani");
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("latest_values application", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("latest_values: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("laniusc_latest_values", "application", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let mut command = Command::new("python3");
    command
        .arg(root.join("tests/fixtures/stdlib_execution/latest_values/oracle.py"))
        .arg(group)
        .arg(executable().path());
    let output = common::process_output_with_timeout(
        "latest_values native application oracle",
        &mut command,
        Duration::from_secs(70),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII finite receipt");
    let prefix = format!("latest-values group={group} cases=");
    let count: usize = summary
        .trim()
        .strip_prefix(&prefix)
        .unwrap_or_else(|| panic!("missing receipt: {summary:?}"))
        .parse()
        .unwrap();
    assert!(count > 0, "no native cases executed");
    print!("{summary}");
}

#[test]
fn latest_values_matches_independent_displaced_history_and_sorted_snapshot_models() {
    gate("models");
}

#[test]
fn latest_values_strict_tsv_utf8_limits_and_committed_history_failure_are_explicit() {
    gate("bounds");
}

#[test]
fn latest_values_reached_ooms_preserve_distinct_precommit_and_history_failure_owners() {
    gate("allocations");
}

#[test]
fn latest_values_io_failures_release_owners_and_report_actual_output_prefixes() {
    gate("faults");
}
