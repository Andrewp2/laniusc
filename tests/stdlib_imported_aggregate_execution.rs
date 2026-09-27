mod common;

use laniusc_compiler::compiler::{
    compile_entry_to_x86_64_with_stdlib,
    type_check_entry_with_stdlib,
};

#[test]
fn imported_aggregate_returns_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_aggregate_root");
    for name in [
        "repro_aggregate_single_app",
        "repro_aggregate_app",
        "repro_aggregate_triple_app",
    ] {
        let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let stdlib_root = stdlib_root.clone();
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

#[test]
fn imported_scalar_result_after_aggregate_argument_uses_correct_abi_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_vec_get_empty.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("imported vector get fallback", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile scalar call after vector argument");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported vector get fallback",
            "repro_vec_get_empty",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(77), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_fieldless_enum_result_uses_aggregate_abi_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_ordering_return.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("imported ordering result", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported fieldless enum result");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported ordering result",
            "repro_ordering_return",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_scalar_payload_enum_result_uses_aggregate_abi_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_enum_payload_app.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_enum_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported enum scalar payload", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported enum with scalar payload");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported enum scalar payload",
            "repro_enum_payload_app",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_unit_variant_of_payload_enum_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_enum_direct_unit_app.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_enum_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported mixed enum unit", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile direct imported unit variant from a mixed enum");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported mixed enum unit",
            "repro_enum_direct_unit_app",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn inferred_imported_enum_values_cross_module_calls_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_enum_inferred_app.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_enum_root");
    let bytes = common::run_gpu_codegen_with_timeout("inferred imported enum", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile inferred imported unit and function-result values");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "inferred imported enum",
            "repro_enum_inferred_app",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn inferred_imported_enum_rejects_other_nominal_type() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_enum_inferred_mismatch.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_enum_root");
    let error = common::run_gpu_codegen_with_timeout("inferred enum mismatch", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect_err("an inferred Maybe must not match an unrelated enum");
    assert!(error.to_string().contains("type mismatch"), "{error}");
}

#[test]
fn inferred_imported_struct_result_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_aggregate_inferred_app.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_aggregate_root");
    let bytes = common::run_gpu_codegen_with_timeout("inferred imported struct", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile inferred imported struct result");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "inferred imported struct",
            "repro_aggregate_inferred_app",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_payload_variant_without_call_is_rejected() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_enum_payload_variant_value.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_enum_root");
    let error = common::run_gpu_codegen_with_timeout("bare imported payload variant", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect_err("a payload-bearing variant must be called with its payload");
    assert!(
        error.to_string().contains("unresolved identifier"),
        "{error}"
    );
}

#[test]
fn direct_imported_payload_constructor_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/repro_enum_direct_payload_constructor_app.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_enum_root");
    let bytes =
        common::run_gpu_codegen_with_timeout("direct imported payload constructor", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .expect("compile a direct imported payload constructor");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "direct imported payload constructor",
            "repro_enum_direct_payload_constructor_app",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_calls_reject_wrong_arity() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for name in [
        "repro_enum_direct_payload_wrong_arity",
        "repro_enum_direct_payload_extra_arity",
        "repro_imported_function_wrong_arity",
    ] {
        let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_enum_root");
        let error = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .expect_err("missing or extra imported call arguments must be rejected");
        assert!(
            error.to_string().contains("wrong number of arguments"),
            "{name}: {error}"
        );
    }
}

#[test]
fn gpu_check_reports_imported_constructor_arity() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for name in [
        "repro_enum_direct_payload_wrong_arity",
        "repro_enum_direct_payload_extra_arity",
    ] {
        let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_enum_root");
        let error = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(type_check_entry_with_stdlib(&entry, &stdlib_root))
        })
        .expect_err("GPU check must reject an imported constructor's wrong arity");
        assert!(
            error.to_string().contains("wrong number of arguments"),
            "{name}: {error}"
        );
    }
}

#[test]
fn imported_payload_constructor_rejects_wrong_type() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_enum_direct_payload_wrong_type.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_enum_root");
    let error = common::run_gpu_codegen_with_timeout("imported payload type", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect_err("a bool cannot fill an i32 enum payload");
    assert!(error.to_string().contains("type mismatch"), "{error}");
}

#[test]
fn imported_flat_struct_payload_enum_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_enum_nested_app.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_enum_nested_root");
    let bytes =
        common::run_gpu_codegen_with_timeout("imported enum flat struct payload", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .expect("compile imported enum with flat struct payload");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported enum flat struct payload",
            "repro_enum_nested_app",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
