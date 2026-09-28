mod common;

use laniusc_compiler::compiler::{
    compile_entry_to_x86_64_with_stdlib,
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
fn concrete_generic_enum_values_execute_on_x86() {
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
        (
            "generic empty variant",
            include_str!("fixtures/stdlib_foundation/repro_generic_enum_local_none.lani"),
        ),
        (
            "generic two-argument payload",
            include_str!("fixtures/stdlib_foundation/repro_generic_enum_local_multi_payload.lani"),
        ),
    ] {
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
        })
        .expect("concrete generic enum should compile");
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn imported_generic_enum_constructor_still_needs_emit_type_projection() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_generic_enum_local_match.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_enum_only_root");
    let error = common::run_gpu_codegen_with_timeout("imported generic enum value", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect_err("imported constructor should fail closed until emit type projection works");
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn imported_option_generic_function_body_still_fails_closed() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_generic_option.lani");
    let stdlib = root.join("stdlib");
    let error = common::run_gpu_codegen_with_timeout("generic Option function body", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect_err("generic Option functions still require concrete specialization");
    assert_eq!(error.to_public_diagnostic().code, "LNC0017", "{error:?}");
}
