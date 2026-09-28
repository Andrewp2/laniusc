mod common;

use laniusc_compiler::compiler::{
    compile_source_pack_to_x86_64_with_gpu_codegen,
    compile_source_to_x86_64_with_gpu_codegen,
};

#[test]
fn unused_generic_enum_declaration_executes_on_x86() {
    let source = include_str!("fixtures/stdlib_foundation/repro_generic_enum_unused.lani");
    let bytes = common::run_gpu_codegen_with_timeout("unused generic enum", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("unused generic enum should compile");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "unused generic enum",
            "repro_generic_enum_unused",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_declaration_only_generic_enum_executes_on_x86() {
    let sources = [
        include_str!("fixtures/stdlib_foundation/repro_generic_enum_only_root/core/maybe.lani"),
        include_str!("fixtures/stdlib_foundation/repro_generic_enum_import_unused.lani"),
    ];
    let bytes = common::run_gpu_codegen_with_timeout("imported declaration-only enum", move || {
        pollster::block_on(compile_source_pack_to_x86_64_with_gpu_codegen(&sources))
    })
    .expect("unused imported generic enum should compile");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported declaration-only enum",
            "repro_generic_enum_import_unused",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn generic_enum_construction_still_requires_concrete_layout() {
    for (name, source) in [
        (
            "generic scalar constructor",
            include_str!("fixtures/stdlib_foundation/repro_generic_enum_construct_only.lani"),
        ),
        (
            "generic scalar match",
            include_str!("fixtures/stdlib_foundation/repro_generic_enum_local_scalar.lani"),
        ),
        (
            "generic wide match",
            include_str!("fixtures/stdlib_foundation/repro_generic_enum_local_wide.lani"),
        ),
    ] {
        let error = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
        })
        .expect_err("used generic enum must not emit an assumed payload layout");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0017",
            "{name}: {error:?}"
        );
    }
}
