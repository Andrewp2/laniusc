//! Direct actual Run; independent archive, filesystem, and pre-exit owner oracle.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    sync::OnceLock,
    time::Duration,
};

fn probe() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/extended/archive_materializer/probe.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("archive materializer owner", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("archive materializer owner: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let executable = common::TempArtifact::new("laniusc_archive_materializer", "exe", None);
        executable.write_bytes(bytes);
        std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700))
            .unwrap();
        executable
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "archive materializer native group",
        Command::new("python3")
            .arg("-B")
            .arg(root.join("tests/fixtures/extended/archive_materializer/oracle.py"))
            .arg(group)
            .arg(probe().path()),
        Duration::from_secs(68),
    );
    common::assert_command_success("archive materializer native group", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII finite native receipt");
    let prefix = format!("archive-materializer group={group} cases=");
    let count: usize = summary
        .trim()
        .strip_prefix(&prefix)
        .unwrap_or_else(|| panic!("missing native case receipt: {summary:?}"))
        .parse()
        .unwrap();
    assert!(count > 0);
    print!("{summary}");
}

#[test]
fn actual_materializer_extracts_ustar_zip_and_raw_views_with_owned_parent_records() {
    gate("success");
}
#[test]
fn actual_materializer_preserves_existing_objects_and_never_opens_regular_leaves() {
    gate("existing");
}
#[test]
fn actual_materializer_records_exact_published_prefix_before_late_failures() {
    gate("partial");
}
#[test]
fn actual_materializer_enforces_active_shared_bounds_and_exact_counter_limits() {
    gate("bounds");
}
#[test]
fn actual_materializer_releases_every_reached_source_allocation_first_half() {
    gate("allocations_first");
}
#[test]
fn actual_materializer_releases_every_reached_source_allocation_second_half() {
    gate("allocations_second");
}
#[test]
fn actual_materializer_records_mkdir_before_reopen_and_metadata_failures() {
    gate("namespace");
}
#[test]
fn actual_materializer_preserves_directory_and_file_sync_failure_receipts() {
    gate("sync");
}
#[test]
fn actual_materializer_bounds_write_interruptions_invalid_counts_and_entropy() {
    gate("writes");
}
#[test]
fn actual_materializer_retires_close_owners_and_preserves_ambiguous_rename() {
    gate("close_rename");
}
#[test]
fn actual_materializer_retains_real_prefix_and_transfers_recovery_without_republication() {
    gate("recovery");
}
