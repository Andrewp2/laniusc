//! Owned LF records through the canonical buffered stdin provider.
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
        let entry = root().join("sample_programs/library/line_report.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("owned delimited input application", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("line report: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "line report requires an actual little-endian ELF64 x86-64 executable"
        );
        let artifact = common::TempArtifact::new("line_report", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("line report {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_foundation/line_report/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("line report {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("line-report-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn line_report_binary_text_records_boundaries_and_buffered_resumption_match_reference() {
    oracle("model", 43);
}
#[test]
fn line_report_invalid_utf8_record_and_aggregate_limits_publish_nothing() {
    oracle("rejection", 33);
}
#[test]
fn line_report_cli_help_numeric_bounds_and_input_bypass_execute() {
    oracle("cli", 34);
}
#[test]
fn line_report_shared_delegation_quota_crosses_records_at_exact_boundary() {
    oracle("quota", 2);
}
#[test]
fn line_report_reached_allocations_io_prefix_and_explicit_cleanup_execute() {
    oracle("io", 19);
}
