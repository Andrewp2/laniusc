#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn sparse_cg_matches_fraction_solutions_fresh_residuals_and_truthful_stops() {
    let entry = root().join("tests/fixtures/extended_library/sparse_cg/model.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("sparse CG independent model", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("sparse CG model: {error}"));
    let executable = common::TempArtifact::new("laniusc_sparse_cg_model", "native", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "sparse CG Fraction Gaussian/fresh residual model",
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended_library/sparse_cg/oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(85),
    );
    common::assert_command_success("sparse CG independent model", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with("sparse-cg cases=1918 storage_forms=2"),
        "{summary}"
    );
    eprint!("{summary}");
}
