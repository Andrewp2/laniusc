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
        let entry = root().join("sample_programs/library/graph_walk.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root().join("stdlib")),
            user_roots: vec![root().join("extended")],
        };
        let bytes =
            common::run_gpu_codegen_with_timeout("sparse graph walk application", move || {
                pollster::block_on(
                    laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                        &entry, &roots,
                    ),
                )
            })
            .unwrap_or_else(|error| panic!("graph walk: {error}"));
        let artifact = common::TempArtifact::new("graph_walk", "executable", None);
        artifact.write_bytes(bytes);
        std::fs::set_permissions(artifact.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}
fn oracle(mode: &str, count: usize) {
    let output = common::process_output_with_timeout(
        format!("graph walk {mode}"),
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/stdlib_execution/graph_walk/oracle.py"))
            .arg(mode)
            .arg(executable().path()),
        Duration::from_secs(85),
    );
    common::assert_command_success(format!("graph walk {mode}"), &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("graph-walk-{mode} cases={count} evidence=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn graph_walk_sparse_storage_and_products_match_dense_fraction_models() {
    oracle("model", 32);
}
#[test]
fn graph_walk_invalid_graphs_and_numerical_failures_publish_no_prefix() {
    oracle("rejection", 33);
}
#[test]
fn graph_walk_cli_and_help_execute() {
    oracle("cli", 38);
}
#[test]
fn graph_walk_actual_io_and_three_reached_allocation_denials_execute() {
    oracle("io", 10);
}
