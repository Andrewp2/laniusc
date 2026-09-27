mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn imported_generic_method_uses_the_concrete_unsigned_receiver() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_u32_range_method.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_u32_range_method_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported u32 method", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported u32 method");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("imported u32 method", "imported_u32_method", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
