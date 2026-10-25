#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

#[test]
fn runtime_rows_distinguish_structural_validity_from_host_binding() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/core_runtime_metadata.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("runtime_metadata", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .expect("compile public runtime metadata consumer");
    let output = common::run_x86_64_elf_output("runtime_metadata", "runtime_metadata", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
