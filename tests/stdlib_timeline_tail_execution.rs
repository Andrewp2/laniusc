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
        let entry = root().join("sample_programs/library/timeline_tail.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("timeline tail application", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("timeline tail: {error}"));
        let artifact = common::TempArtifact::new("timeline_tail", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("timeline tail {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/timeline_tail/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(80),
    );
    common::assert_command_success(format!("timeline tail {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("timeline-tail-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn timeline_tail_reverses_filters_takes_enumerates_and_encodes_against_model() {
    oracle("model", 25);
}
#[test]
fn timeline_tail_invalid_unselected_csv_and_limits_publish_no_prefix() {
    oracle("rejection", 24);
}
#[test]
fn timeline_tail_cli_and_help_execute() {
    oracle("cli", 20);
}
#[test]
fn timeline_tail_real_input_and_output_failures_execute() {
    oracle("io", 2);
}
