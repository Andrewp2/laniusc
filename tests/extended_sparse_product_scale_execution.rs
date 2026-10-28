//! Analytic sparse/sparse fill-in over an implicit square of over four billion cells.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};

#[test]
fn large_tridiagonal_sparse_square_has_exact_fill_in_and_analytic_products() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/extended_library/sparse_product/scale.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("sparse product analytic scale", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("sparse product analytic scale: {error}"));
    let executable = common::TempArtifact::new("laniusc_sparse_product_scale", "executable", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();

    // Time the complete native process: construction, multiplication, full
    // analytic validation, two matvecs and explicit destruction. Compilation
    // is outside this clock; this observation is not multiplication throughput.
    let started = Instant::now();
    let output = common::process_output_with_timeout(
        "65,536-row analytic sparse-product lifecycle",
        &mut Command::new(executable.path()),
        Duration::from_secs(60),
    );
    let elapsed = started.elapsed();
    common::assert_command_success("analytic sparse square/fill-in/products", &output);
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    eprintln!(
        "sparse-product-scale rows=65536 cols=65536 input-nnz=196606 output-nnz=327674 structural-products=589814 admitted-work=23330433 implicit-dense-cells=4294967296 native-lifecycle-ms={:.3}",
        elapsed.as_secs_f64() * 1000.0
    );
}
