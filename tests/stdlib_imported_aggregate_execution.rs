mod common;

use laniusc_compiler::compiler::{
    compile_entry_to_x86_64_with_stdlib,
    type_check_entry_with_stdlib,
};

#[test]
fn imported_associated_constructor_returns_aggregate_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_imported_associated_new.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_imported_associated_new_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported Thing::new", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported associated constructor");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported Thing::new",
            "repro_imported_associated_new",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout: {output:?}");
        assert!(output.stderr.is_empty(), "unexpected stderr: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_plain_instance_method_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_imported_plain_method.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_imported_associated_new_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported Thing::get", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported instance method");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported Thing::get",
            "repro_imported_plain_method",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout: {output:?}");
        assert!(output.stderr.is_empty(), "unexpected stderr: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_instance_method_on_inferred_value_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_imported_plain_method_inferred.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_imported_associated_new_root");
    let bytes = common::run_gpu_codegen_with_timeout("inferred imported Thing::get", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported method on inferred value");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "inferred imported Thing::get",
            "repro_imported_plain_method_inferred",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout: {output:?}");
        assert!(output.stderr.is_empty(), "unexpected stderr: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_calls_with_seven_to_nine_arguments_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_seven_arguments.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_many_args_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported stack arguments", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported stack arguments");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported stack arguments",
            "repro_seven_arguments",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "unexpected stdout: {output:?}");
        assert!(output.stderr.is_empty(), "unexpected stderr: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_stack_arguments_with_hidden_aggregate_return_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_many_args_aggregate_return.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_many_args_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported stack aggregate", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported stack aggregate");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported stack aggregate",
            "repro_many_args_aggregate_return",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

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
fn local_helpers_forward_imported_option_and_result_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for name in [
        "repro_option_u16_local_return",
        "option_result_u16_local_returns",
        "option_result_f32_local_returns",
    ] {
        let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: compile: {error}"));

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
fn imported_concrete_option_and_result_returns_cover_payload_widths_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("stdlib");
    for (module, ty, value) in [
        ("i8", "i8", "-128"),
        ("u8", "u8", "255"),
        ("i16", "i16", "-32768"),
        ("u16", "u16", "65535"),
        ("i32", "i32", "-2147483648"),
        ("u32", "u32", "4294967295"),
        ("bool", "bool", "false"),
        ("f32", "f32", "-2.5"),
    ] {
        let source = format!(
            "module app::main;\n\
             import core::option;\n\
             import core::result;\n\
             fn forward_option(value: {ty}) -> core::option::Option<{ty}> {{\n\
                 return core::option::Some(value);\n\
             }}\n\
             fn forward_result(value: {ty}) -> core::result::Result<{ty}, {ty}> {{\n\
                 return core::result::Ok(value);\n\
             }}\n\
             fn main() -> i32 {{\n\
                 let value: {ty} = {value};\n\
                 let option: core::option::Option<{ty}> = forward_option(value);\n\
                 if (!core::option::contains(option, value)) {{ return 1; }}\n\
                 let result: core::result::Result<{ty}, {ty}> = forward_result(value);\n\
                 if (!core::result::contains(result, value)) {{ return 2; }}\n\
                 return 0;\n\
             }}\n"
        );
        let temp = common::TempArtifact::new("laniusc", &format!("forward_{module}"), Some("lani"));
        temp.write_str(&source);
        let entry = temp.path().to_owned();
        let stdlib_root = stdlib_root.clone();
        let label = format!("local imported {module} Option/Result return");
        let bytes = common::run_gpu_codegen_with_timeout(&label, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{label}: compile: {error}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output =
                common::run_x86_64_elf_output(&label, &format!("forward_{module}"), &bytes);
            assert_eq!(output.status.code(), Some(0), "{label}: {output:?}");
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
