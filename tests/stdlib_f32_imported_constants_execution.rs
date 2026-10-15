mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn imported_f32_constants_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let name = "literal";
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_f32_const.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_f32_const_root");
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

// Computed IEEE constants (`1.25 + 0.5`) are rejected by design until a portable
// IEEE evaluator exists (docs/compiler-generic-types.md, floating payload
// checkpoint), as native_float_payload_reject_computed_constant checks locally.
#[test]
fn imported_computed_f32_constants_are_rejected() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/f32_imported_const_expr.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/f32_imported_const_expr_root");
    let error = common::run_gpu_codegen_with_timeout("expressions", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect_err("a computed f32 constant must not emit an executable");
    let diagnostic = error.to_public_diagnostic();
    assert_eq!(diagnostic.code, "LNC0071", "{error:?}");
    let label = diagnostic
        .primary_label
        .as_ref()
        .expect("LNC0071 has a primary label");
    assert!(label.path.ends_with("core/constants.lani"), "{error:?}");
    assert_eq!(
        label.line, 4,
        "the first computed constant is SUM: {error:?}"
    );
}
