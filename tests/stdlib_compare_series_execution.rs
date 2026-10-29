//! Bounded signed series against independent tuple and adjacency predicates.
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
        let entry = root().join("sample_programs/library/compare_series.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout(
            "iterator series comparison application",
            move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            },
        )
        .unwrap_or_else(|error| panic!("compare series: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "compare series requires an actual little-endian ELF64 x86-64 executable"
        );
        let artifact = common::TempArtifact::new("compare_series", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("compare series {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_foundation/compare_series/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("compare series {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("compare-series-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn compare_series_signed_lists_prefix_order_sortedness_and_caps_match_reference() {
    oracle("model", 44);
}
#[test]
fn compare_series_invalid_csv_numeric_and_combined_input_limits_publish_nothing() {
    oracle("rejection", 35);
}
#[test]
fn compare_series_cli_aliases_duplicates_and_help_input_bypass_execute() {
    oracle("cli", 19);
}
#[test]
fn compare_series_reached_allocations_io_and_prepublication_retirement_execute() {
    oracle("io", 21);
}
