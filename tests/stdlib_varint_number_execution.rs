//! Strict scalar varint CLI against independent arbitrary-precision integers.
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
        let entry = root().join("sample_programs/library/varint_number.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("native varint scalar application", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("varint number: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "varint number must compile to an actual little-endian ELF64 x86-64 executable"
        );
        let artifact = common::TempArtifact::new("varint_number", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("varint number {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/varint_number/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("varint number {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("varint-number-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn varint_number_all_modes_and_width_boundaries_match_independent_integer_model() {
    oracle("model", 76);
}
#[test]
fn varint_number_noncanonical_overflow_truncation_and_trailing_wire_reject() {
    oracle("wire", 30);
}
#[test]
fn varint_number_strict_cli_and_help_preflight_execute() {
    oracle("cli", 34);
}
#[test]
fn varint_number_reached_argument_allocations_output_failures_and_cleanup_execute() {
    oracle("io", 10);
}
