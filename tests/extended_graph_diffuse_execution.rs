//! Bounded graph diffusion against independent dense linear-system models.
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
        let entry = root().join("sample_programs/library/graph_diffuse.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("graph diffusion application", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("graph diffusion: {error}"));
        let artifact = common::TempArtifact::new("graph_diffuse", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("graph diffusion {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/graph_diffuse/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("graph diffusion {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("graph-diffuse-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn graph_diffusion_solutions_match_dense_fraction_elimination_and_true_residuals() {
    oracle("model", 36);
}
#[test]
fn graph_diffusion_rejects_invalid_inputs_work_limits_and_unconverged_results() {
    oracle("rejection", 48);
}
#[test]
fn graph_diffusion_cli_and_help_execute() {
    oracle("cli", 55);
}
#[test]
fn graph_diffusion_io_reached_cg_workspace_failures_and_observed_cleanup_execute() {
    oracle("io", 15);
}
