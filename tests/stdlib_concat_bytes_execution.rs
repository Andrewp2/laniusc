//! Real-file concatenation prefixes and bounded reader-adapter application I/O.
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
        let entry = root().join("sample_programs/library/concat_bytes.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout(
            "borrowed reader-adapter application",
            move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            },
        )
        .unwrap_or_else(|error| panic!("concat bytes: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "concat bytes must produce an actual little-endian ELF64 x86-64 executable"
        );
        let artifact = common::TempArtifact::new("concat_bytes", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("concat bytes {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/concat_bytes/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("concat bytes {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("concat-bytes-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn concat_bytes_two_real_files_match_independent_prefix_model() {
    oracle("model", 29);
}
#[test]
fn concat_bytes_zero_and_maximum_quotas_bound_actual_source_requests() {
    oracle("limits", 12);
}
#[test]
fn concat_bytes_cli_help_and_invalid_limits_precede_file_opens() {
    oracle("cli", 45);
}
#[test]
fn concat_bytes_reached_allocation_io_failures_and_publication_cleanup_execute() {
    oracle("io", 29);
}
