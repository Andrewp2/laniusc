//! Actual owning nested-iteration application with independent arithmetic and strict source-owner traces.
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
        let entry = root.join("sample_programs/library/flatten_sum.lani");
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("flatten_sum application", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("flatten_sum: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("laniusc_flatten_sum", "application", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let mut command = Command::new("python3");
    command
        .arg(root.join("tests/fixtures/stdlib_execution/flatten_sum/oracle.py"))
        .arg(group)
        .arg(executable().path());
    let output = common::process_output_with_timeout(
        "flatten_sum native application oracle",
        &mut command,
        Duration::from_secs(70),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII finite receipt");
    let prefix = format!("flatten-sum group={group} cases=");
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
fn flatten_sum_prefix_totals_match_independent_nested_rows_and_empty_owners() {
    gate("models");
}

#[test]
fn flatten_sum_input_argument_caps_and_arithmetic_failures_publish_nothing() {
    gate("bounds");
}

#[test]
fn flatten_sum_all_reached_ooms_release_partial_rows_and_every_owner() {
    gate("allocations");
}

#[test]
fn flatten_sum_output_and_read_faults_preserve_exact_prefix_and_cleanup() {
    gate("faults");
}
