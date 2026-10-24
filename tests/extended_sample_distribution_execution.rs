#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};
fn executable() -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/sample_distribution.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("sample-distribution", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap();
    let exe = common::TempArtifact::new("laniusc_sampling", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn real_csv_sampling_statistics_staging_and_fault_cleanup() {
    let exe = executable();
    let output = common::process_output_with_timeout(
        "sampling real CSV consumer",
        Command::new("python3")
            .args([
                "-c",
                include_str!("fixtures/extended/sampling_cli_oracle.py"),
            ])
            .arg(exe.path()),
        Duration::from_secs(40),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}
#[test]
fn closed_output_pipes_and_signal_setup_failures_preserve_cleanup_and_status() {
    let exe = executable();
    let output = common::process_output_with_timeout(
        "sampling actual broken pipes and signal setup",
        Command::new("python3")
            .args([
                "-c",
                include_str!("fixtures/extended/sampling_signal_oracle.py"),
            ])
            .arg(exe.path()),
        Duration::from_secs(15),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}
