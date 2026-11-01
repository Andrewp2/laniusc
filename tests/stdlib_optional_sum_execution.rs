//! Optional-field composition through bounded native input and exact CSV output.
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
        let entry = root().join("sample_programs/library/optional_sum.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("optional field sum application", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("optional sum: {error}"));
        let artifact = common::TempArtifact::new("optional_sum", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("optional sum {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/optional_sum/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("optional sum {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("optional-sum-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn optional_sum_missing_present_full_width_and_boundaries_match_independent_model() {
    oracle("model", 33);
}
#[test]
fn optional_sum_invalid_records_overflow_and_limits_publish_no_output() {
    oracle("rejection", 30);
}
#[test]
fn optional_sum_cli_and_help_execute() {
    oracle("cli", 17);
}
#[test]
fn optional_sum_io_retries_reached_allocations_and_actual_partial_output_execute() {
    oracle("io", 18);
}
