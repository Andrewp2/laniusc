#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

#[test]
fn sparse_product_matches_dense_fraction_and_ordered_ieee_models() {
    let entry = root().join("tests/fixtures/extended_library/sparse_product/model.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: vec![root().join("extended")],
    };
    let bytes =
        common::run_gpu_codegen_with_timeout("sparse product independent model", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|error| panic!("sparse product model: {error}"));
    let executable = common::TempArtifact::new("laniusc_sparse_product_model", "native", None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let output = common::process_output_with_timeout(
        "sparse product dense-dictionary/Fraction/IEEE model",
        Command::new("python3")
            .arg("-B")
            .arg(root().join("tests/fixtures/extended_library/sparse_product/oracle.py"))
            .arg(executable.path()),
        Duration::from_secs(85),
    );
    common::assert_command_success("sparse product independent model", &output);
    assert!(output.stderr.is_empty(), "{output:?}");
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with("sparse-product cases=2194 storage_forms=2"),
        "{summary}"
    );
    eprint!("{summary}");
}
