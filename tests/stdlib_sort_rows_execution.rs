//! CSV ordering and stable library ties over allocation-backed slice sort.
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
        let entry = root().join("sample_programs/library/sort_rows.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("CSV row sorting application", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("sort rows: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "sort rows must compile to an actual x86_64 ELF executable"
        );
        let artifact = common::TempArtifact::new("sort_rows", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("sort rows {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/sort_rows/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("sort rows {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("sort-rows-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn sort_rows_text_numeric_headers_and_stable_ties_match_independent_sorted_model() {
    oracle("model", 37);
}
#[test]
fn sort_rows_malformed_csv_keys_and_limits_publish_no_output() {
    oracle("rejection", 33);
}
#[test]
fn sort_rows_cli_and_help_execute() {
    oracle("cli", 39);
}
#[test]
fn sort_rows_native_io_reached_allocation_denials_and_observed_releases_execute() {
    oracle("io", 14);
}
