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
        let entry = root().join("sample_programs/library/sample_moments.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("sample moments application", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("sample moments: {error}"));
        let artifact = common::TempArtifact::new("sample_moments", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("sample moments {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/sample_moments/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("sample moments {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("sample-moments-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn sample_moments_weighted_and_unweighted_profiles_match_exact_reference() {
    oracle("model", 26);
}
#[test]
fn sample_moments_invalid_csv_inputs_and_unrepresentable_moments_publish_nothing() {
    oracle("rejection", 30);
}
#[test]
fn sample_moments_cli_and_help_execute() {
    oracle("cli", 8);
}
#[test]
fn sample_moments_input_and_output_failures_execute() {
    oracle("io", 2);
}
