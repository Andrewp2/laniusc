//! Complete archive admission and manual source ownership in real Lanius code.
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
        let entry = root.join("tests/fixtures/extended/archive_source/probe.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("archive source probe", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("archive source probe: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let executable = common::TempArtifact::new("laniusc_archive_source", "probe", None);
        executable.write_bytes(bytes);
        std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700))
            .unwrap();
        executable
    })
}

fn gate(group: &str) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        "archive source native oracle",
        Command::new("python3")
            .arg("-B")
            .arg(root.join("tests/fixtures/extended/archive_source/oracle.py"))
            .arg(group)
            .arg(probe().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success("archive source native oracle", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).expect("ASCII native receipt");
    let prefix = format!("PASS archive-source group={group} process-cases=");
    let accepted: Vec<usize> = summary
        .lines()
        .filter_map(|line| line.strip_prefix(&prefix))
        .map(|count| count.parse().expect("finite native case count"))
        .collect();
    assert_eq!(
        accepted.len(),
        1,
        "missing/duplicate native receipt: {summary}"
    );
    assert!(accepted[0] > 0, "no native archive source cases executed");
    print!("{summary}");
}

#[test]
fn archive_source_tar_seals_full_metadata_and_preserves_borrowed_binary_payloads() {
    gate("tar");
}

#[test]
fn archive_source_zip_separates_metadata_admission_from_payload_integrity() {
    gate("zip");
}

#[test]
fn archive_source_limits_preflight_owned_bytes_and_independent_work_budgets() {
    gate("limits");
}

#[test]
fn archive_source_reached_allocation_failures_release_staged_owners_before_exit() {
    gate("allocations");
}
