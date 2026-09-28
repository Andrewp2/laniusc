mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn generic_vector_capability_and_concrete_fallback_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/vec_capability.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("vec_capability", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("vec_capability: compile: {error}"));

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("vec_capability", "vec_capability", &bytes);
        assert_eq!(output.status.code(), Some(0), "vec_capability: {output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout");
        assert!(output.stderr.is_empty(), "unexpected stderr");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_generic_vector_capability_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/std/vec.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/vec_capability.lani");
    let names = [
        "vec_runtime_abi_version",
        "vec_service_id",
        "vec_service_is_known",
        "vec_service_status",
        "vec_is_available",
        "vec_requires_runtime_binding",
    ];
    for name in names {
        assert!(source.contains(&format!("pub fn {name}(")));
        assert!(
            fixture.contains(&format!("std::vec::{name}(")),
            "std::vec::{name} lacks a runtime case"
        );
    }
}
