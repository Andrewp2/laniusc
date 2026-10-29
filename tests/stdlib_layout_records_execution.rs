//! Checked record layouts, actual arena storage and binary report admission.
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
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let entry = root().join("sample_programs/library/layout_records.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout(
            "checked layout record storage application",
            move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            },
        )
        .unwrap_or_else(|error| panic!("layout records: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "layout records must compile to an actual little-endian ELF64 x86-64 executable"
        );
        let artifact = common::TempArtifact::new("layout_records", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("layout records {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/layout_records/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("layout records {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("layout-records-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn layout_records_storage_counts_and_boundaries_match_independent_byte_model() {
    oracle("model", 20);
}
#[test]
fn layout_records_strict_count_cli_and_help_execute() {
    oracle("cli", 28);
}
#[test]
fn layout_records_reached_owner_faults_output_retries_and_cleanup_execute() {
    oracle("io", 10);
}
