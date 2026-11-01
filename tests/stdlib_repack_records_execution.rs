//! Byte-exact record conversion, framing admission and native I/O failures.
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
        let entry = root().join("sample_programs/library/repack_records.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("native endian record application", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("repack records: {error}"));
        let artifact = common::TempArtifact::new("repack_records", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("repack records {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/repack_records/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("repack records {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("repack-records-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn repack_records_all_orders_preserve_integer_and_ieee_payload_bits() {
    oracle("model", 27);
}
#[test]
fn repack_records_invalid_frames_publish_no_output() {
    oracle("rejection", 30);
}
#[test]
fn repack_records_cli_and_help_execute() {
    oracle("cli", 23);
}
#[test]
fn repack_records_io_prefix_failures_allocation_cleanup_and_attempt_caps_execute() {
    oracle("io", 16);
}
