//! Large manufactured sparse SPD solve with independent band residual checks.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};

#[test]
fn large_manufactured_sparse_spd_system_converges_with_independent_true_residual() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/extended_library/sparse_cg/scale.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("sparse CG analytic scale", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("sparse CG analytic scale: {error}"));
    let executable = common::TempArtifact::new("laniusc_sparse_cg_scale", "executable", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();

    // The observation covers the entire native process: construction, solve,
    // input-preservation checks, independent residual/solution checks and
    // destruction. It excludes compilation and is not a solver throughput rate.
    let started = Instant::now();
    let output = common::process_output_with_timeout(
        "65,536-row manufactured sparse-CG lifecycle",
        &mut Command::new(executable.path()),
        Duration::from_secs(60),
    );
    let elapsed = started.elapsed();
    common::assert_command_success(
        "manufactured sparse CG and independent true residual",
        &output,
    );
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    eprintln!(
        "sparse-cg-scale rows=65536 cols=65536 nnz=196606 max-iterations=20 rtol=1e-10 admitted-work=90833350 implicit-dense-cells=4294967296 native-lifecycle-ms={:.3}",
        elapsed.as_secs_f64() * 1000.0
    );
}
