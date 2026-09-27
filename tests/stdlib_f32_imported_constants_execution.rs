mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn imported_f32_constants_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, entry, stdlib_root) in [
        (
            "literal",
            "tests/fixtures/stdlib_foundation/repro_f32_const.lani",
            "tests/fixtures/stdlib_foundation/repro_f32_const_root",
        ),
        (
            "expressions",
            "tests/fixtures/stdlib_foundation/f32_imported_const_expr.lani",
            "tests/fixtures/stdlib_foundation/f32_imported_const_expr_root",
        ),
    ] {
        let entry = root.join(entry);
        let stdlib_root = root.join(stdlib_root);
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: compile imported f32 constants: {error}"));

        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = bytes;
    }
}
