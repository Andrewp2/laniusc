mod common;

use laniusc_compiler::compiler::compile_source_pack_to_x86_64_with_gpu_codegen;

#[test]
fn generic_vec_empty_from_flat_source_pack_executes() {
    let sources = [
        include_str!("../stdlib/std/vec.lani"),
        include_str!("fixtures/stdlib_foundation/repro_vec_generic_associated_new.lani"),
    ];
    let bytes = common::run_gpu_codegen_with_timeout("generic vec empty", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("compile generic vec empty");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("generic vec empty", "generic_vec_empty", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn generic_vec_free_new_from_flat_source_pack_executes() {
    let sources = [
        include_str!("../stdlib/std/vec.lani"),
        include_str!("fixtures/stdlib_foundation/repro_vec_generic_free_new.lani"),
    ];
    let bytes = common::run_gpu_codegen_with_timeout("generic vec free", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("compile generic vec free new");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("generic vec free", "generic_vec_free", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn generic_vector_empty_functions_have_flat_runtime_calls() {
    let source = include_str!("../stdlib/std/vec.lani");
    let free = include_str!("fixtures/stdlib_foundation/repro_vec_generic_free_new.lani");
    let associated =
        include_str!("fixtures/stdlib_foundation/repro_vec_generic_associated_new.lani");
    for name in ["new", "len", "is_empty"] {
        assert!(source.contains(&format!("pub fn {name}")));
        assert!(free.contains(&format!("std::vec::{name}(")));
        if name == "new" {
            assert!(associated.contains("Vec<i32>::new("));
        } else {
            assert!(associated.contains(&format!("value.{name}(")));
        }
    }
}
