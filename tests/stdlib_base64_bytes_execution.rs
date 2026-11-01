//! Four strict Base64 profiles against independent canonical byte references.
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
        let entry = root().join("sample_programs/library/base64_bytes.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("checked Base64 binary application", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("base64 bytes: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "base64 bytes must compile to an actual little-endian ELF64 x86-64 executable"
        );
        let artifact = common::TempArtifact::new("base64_bytes", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("base64 bytes {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/base64_bytes/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("base64 bytes {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("base64-bytes-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn base64_bytes_four_profiles_binary_vectors_and_caps_match_canonical_reference() {
    oracle("model", 100);
}
#[test]
fn base64_bytes_noncanonical_invalid_profiles_and_input_limits_publish_nothing() {
    oracle("rejection", 56);
}
#[test]
fn base64_bytes_strict_cli_and_help_preflight_execute() {
    oracle("cli", 20);
}
#[test]
fn base64_bytes_reached_allocations_io_failures_prefix_and_cleanup_execute() {
    oracle("io", 18);
}
