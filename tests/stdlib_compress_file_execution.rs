//! Streaming compression into a bounded AtomicFile with explicit visibility.
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
        let entry = root().join("sample_programs/library/compress_file.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout(
            "atomic compressor application",
            move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            },
        )
        .unwrap_or_else(|error| panic!("compress file: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "compress file must produce an actual little-endian ELF64 x86-64 executable"
        );
        let artifact = common::TempArtifact::new("compress_file", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: Option<usize>) {
    let output = common::process_output_with_timeout(
        format!("compress file {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_compress_file/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("compress file {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    let prefix = match count {
        Some(n) => format!("compress-file-{mode} cases={n} reached_allocations="),
        None => format!("compress-file-{mode} cases="),
    };
    assert!(summary.starts_with(&prefix), "{summary}");
    eprint!("{summary}");
}
#[test]
fn compress_file_independent_formats_block_edges_and_fixed_workspace_execute() { oracle("model", Some(17)); }
#[test]
fn compress_file_no_follow_and_no_replace_preserve_existing_files() { oracle("input_kinds", Some(9)); }
#[test]
fn compress_file_cli_help_raw_paths_and_diagnostic_failures_execute() { oracle("cli", Some(39)); }
#[test]
fn compress_file_exact_input_cap_and_real_excess_byte_probe_execute() { oracle("input_limits", Some(2)); }
#[test]
fn compress_file_reached_oom_io_budgets_and_publication_recovery_execute() { oracle("faults", None); }
