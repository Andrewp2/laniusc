mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn all_concrete_vector_truncations_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/vec_truncate_all.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("vec_truncate_all", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile concrete vector truncation fixture");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("vec_truncate_all", "vec_truncate_all", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn each_concrete_vector_truncation_has_a_runtime_case() {
    let fixture = include_str!("fixtures/stdlib_foundation/vec_truncate_all.lani");
    for (module, source) in [
        ("vec_i32", include_str!("../stdlib/std/vec_i32.lani")),
        ("vec_u32", include_str!("../stdlib/std/vec_u32.lani")),
        ("vec_u8", include_str!("../stdlib/std/vec_u8.lani")),
        ("vec_i8", include_str!("../stdlib/std/vec_i8.lani")),
        ("vec_u16", include_str!("../stdlib/std/vec_u16.lani")),
        ("vec_i16", include_str!("../stdlib/std/vec_i16.lani")),
        ("vec_bool", include_str!("../stdlib/std/vec_bool.lani")),
    ] {
        assert!(
            source.contains("pub fn truncate("),
            "{module} lacks truncate"
        );
        let call = format!("std::{module}::truncate(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
    }
}
