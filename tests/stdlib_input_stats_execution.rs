//! Owned byte/text collection through stdin and real borrowed file readers.
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
        let entry = root().join("sample_programs/library/input_stats.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("owned input statistics application", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("input stats: {error}"));
        assert!(
            common::x86_jumps::is_x86_64_executable(&bytes),
            "input stats requires an actual little-endian ELF64 x86-64 executable"
        );
        let artifact = common::TempArtifact::new("input_stats", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("input stats {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/input_stats/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("input stats {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("input-stats-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn input_stats_binary_utf8_files_and_cap_counts_match_independent_reference() {
    oracle("model", 38);
}
#[test]
fn input_stats_malformed_utf8_and_excess_input_publish_nothing() {
    oracle("rejection", 24);
}
#[test]
fn input_stats_strict_cli_help_and_literal_paths_execute() {
    oracle("cli", 22);
}
#[test]
fn input_stats_reached_storage_faults_io_prefix_and_cleanup_execute() {
    oracle("io", 27);
}
