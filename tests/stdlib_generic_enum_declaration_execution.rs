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
fn imported_generic_enum_constructor_emits_and_passes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_imported_generic_enum_construct_only.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_enum_only_root");
    let bytes =
        common::run_gpu_codegen_with_timeout("imported generic enum constructor", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect("imported generic enum constructor should compile");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported generic enum constructor",
            "repro_imported_generic_enum_construct_only",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_unit_enum_match_checks_discriminants_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_imported_unit_match.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("imported unit match", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("imported unit match should compile");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported unit match",
            "repro_imported_unit_match",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_unit_enum_pattern_rejects_unrelated_scrutinee() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_unit_match_wrong_enum.lani");
    let stdlib = root.join("stdlib");
    let error = common::run_gpu_codegen_with_timeout("unrelated imported pattern", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect_err("a pattern from a different enum must be rejected");
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn unqualified_imported_unit_pattern_rejects_unrelated_scrutinee() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(
        "tests/fixtures/stdlib_foundation/repro_imported_unit_match_unqualified_wrong_enum.lani",
    );
    let stdlib = root.join("stdlib");
    let result = common::run_gpu_codegen_with_timeout("unqualified unrelated pattern", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    });
    let error = match result {
        Err(error) => error,
        Ok(_) => panic!("an unqualified imported pattern from another enum must be rejected"),
    };
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn imported_unit_enum_pattern_rejects_scalar_scrutinee() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_imported_unit_match_scalar.lani");
    let stdlib = root.join("stdlib");
    let result = common::run_gpu_codegen_with_timeout("scalar imported pattern", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    });
    let error = match result {
        Err(error) => error,
        Ok(_) => panic!("an enum pattern against a scalar must be rejected"),
    };
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn imported_unit_enum_pattern_rejects_inferred_scalar_scrutinee() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_imported_unit_match_inferred_scalar.lani");
    let stdlib = root.join("stdlib");
    let result =
        common::run_gpu_codegen_with_timeout("inferred scalar imported pattern", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        });
    let error = match result {
        Err(error) => error,
        Ok(_) => panic!("an enum pattern against an inferred scalar must be rejected"),
    };
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn imported_unit_enum_pattern_rejects_payload_binding() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_unit_match_payload.lani");
    let stdlib = root.join("stdlib");
    let result = common::run_gpu_codegen_with_timeout("unit variant payload binding", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    });
    let error = match result {
        Err(error) => error,
        Ok(_) => panic!("a unit variant cannot bind a payload"),
    };
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn imported_unit_enum_match_direct_call_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_unit_match_direct_call.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("direct call enum match", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("direct imported Ordering return should match");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "direct call enum match",
            "repro_imported_unit_match_direct_call",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_unit_enum_pattern_rejects_unrelated_call_result() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_unit_match_wrong_call.lani");
    let stdlib = root.join("stdlib");
    let result = common::run_gpu_codegen_with_timeout("unrelated call enum match", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    });
    let error = match result {
        Err(error) => error,
        Ok(_) => panic!("an imported pattern must reject a call returning another enum"),
    };
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn imported_generic_enum_uses_maximum_variant_abi_width_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_generic_choice_abi.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_choice_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported generic enum ABI", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("imported generic enum ABI should compile");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported generic enum ABI",
            "repro_imported_generic_choice_abi",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_generic_enum_match_still_needs_pattern_projection() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_generic_enum_local_match.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_enum_only_root");
    let error = common::run_gpu_codegen_with_timeout("imported generic enum value", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect_err("imported enum match patterns still need dependency projection");
    assert_eq!(error.to_public_diagnostic().code, "LNC0005", "{error:?}");
}

#[test]
fn imported_generic_unit_pattern_checks_discriminant_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_generic_enum_none_pattern.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_enum_only_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported generic None pattern", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("an imported generic unit pattern should use the scrutinee's type arguments");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported generic None pattern",
            "repro_imported_generic_enum_none_pattern",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_generic_unit_constructor_preserves_enum_abi_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_generic_enum_none_call.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_enum_only_root");
    let bytes =
        common::run_gpu_codegen_with_timeout("imported generic None constructor", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect("annotated imported generic unit constructor should compile");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported generic None constructor",
            "repro_imported_generic_enum_none_call",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_generic_unit_constructor_requires_concrete_result_type() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_imported_generic_enum_none_unannotated.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_enum_only_root");
    let error =
        common::run_gpu_codegen_with_timeout("unannotated imported generic None", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect_err("a generic unit constructor needs a concrete result type for its ABI");
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn imported_generic_payload_constructor_requires_concrete_result_type() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_imported_generic_enum_some_unannotated.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_enum_only_root");
    let error =
        common::run_gpu_codegen_with_timeout("unannotated imported generic Some", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect_err("a generic payload constructor needs a concrete result type for its ABI");
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn imported_generic_unit_constructor_direct_argument_is_rejected() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(
        "tests/fixtures/stdlib_foundation/repro_imported_generic_enum_none_direct_argument.lani",
    );
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_enum_only_root");
    let error =
        common::run_gpu_codegen_with_timeout("direct imported generic None argument", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect_err("a nested generic unit constructor needs argument-context projection");
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn imported_generic_unit_variant_is_not_a_bare_value() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_imported_generic_enum_bare_none.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_enum_only_root");
    let result = common::run_gpu_codegen_with_timeout("bare imported generic None", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    });
    let error = match result {
        Err(error) => error,
        Ok(_) => panic!("bare imported None must not be emitted without contextual width"),
    };
    assert_eq!(error.to_public_diagnostic().code, "LNC0005", "{error:?}");
}

#[test]
fn imported_generic_unit_pattern_rejects_scalar_scrutinee() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(
        "tests/fixtures/stdlib_foundation/repro_imported_generic_enum_none_wrong_scrutinee.lani",
    );
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_enum_only_root");
    let result = common::run_gpu_codegen_with_timeout("generic None against scalar", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    });
    let error = match result {
        Err(error) => error,
        Ok(_) => panic!("an imported generic enum pattern must reject a scalar"),
    };
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn imported_generic_enum_rejects_wrong_payload_type() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_imported_generic_enum_wrong_payload.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_enum_only_root");
    let error = common::run_gpu_codegen_with_timeout("wrong imported enum payload", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect_err("Maybe<i32>::Some(true) must be rejected");
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn imported_generic_enum_rejects_wrong_second_payload_type() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_imported_generic_choice_wrong_second.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_generic_choice_root");
    let error = common::run_gpu_codegen_with_timeout("wrong second enum payload", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect_err("Choice<i32,bool>::Both(3,9) must be rejected");
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
