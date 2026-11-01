//! Streaming decompression into a bounded AtomicFile with explicit visibility.
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
        let entry = root().join("sample_programs/library/decompress_file.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout(
            "atomic decompressor application",
            move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            },
        )
        .unwrap_or_else(|error| panic!("decompress file: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "decompress file must produce an actual little-endian ELF64 x86-64 executable"
        );
        let artifact = common::TempArtifact::new("decompress_file", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: Option<usize>) {
    let output = common::process_output_with_timeout(
        format!("decompress file {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/decompress_file/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("decompress file {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    let prefix = match count {
        Some(n) => format!("decompress-file-{mode} cases={n} reached_allocations="),
        None => format!("decompress-file-{mode} cases="),
    };
    assert!(summary.starts_with(&prefix), "{summary}");
    eprint!("{summary}");
}
#[test]
fn decompress_file_independent_formats_and_no_replace_preserve_destinations() { oracle("model", Some(15)); }
#[test]
fn decompress_file_bad_streams_and_input_kinds_leave_existing_files_untouched() { oracle("rejection", Some(15)); }
#[test]
fn decompress_file_cli_validated_help_and_diagnostic_failures_execute() { oracle("cli", Some(37)); }
#[test]
fn decompress_file_exact_compressed_cap_and_excess_byte_probe_execute() { oracle("input_limits", Some(2)); }
#[test]
fn decompress_file_gzip_member_limit_admits_exact_bound() { oracle("member_limits", Some(2)); }
#[test]
fn decompress_file_decoded_output_limit_aborts_publication() { oracle("output_limit", Some(1)); }
#[test]
fn decompress_file_reached_allocation_host_and_publication_recovery_failures_execute() { oracle("faults", None); }
