mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn indexed_stores_follow_lvalue_element_type_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for name in [
        "repro_u8_cast_store",
        "repro_u8_cast_store_named_local",
        "repro_i32_index_store",
        "slice_sequence",
        "core_slice_u8",
        "core_slice_u8_complete",
    ] {
        let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: compile: {error}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert!(output.stdout.is_empty(), "{name}: unexpected stdout");
            assert!(output.stderr.is_empty(), "{name}: unexpected stderr");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}
