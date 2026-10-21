mod common;

use laniusc_compiler::compiler::{
    compile_entry_to_x86_64_with_stdlib,
    compile_source_to_x86_64_with_gpu_codegen,
};

#[test]
fn concrete_generic_enum_return_executes_on_x86() {
    let source = r#"
pub enum Maybe<T> { Some(T), None }
fn preserve(value: Maybe<bool>) -> Maybe<bool> { return value; }
fn main() -> i32 {
    let value: Maybe<bool> = Some(false);
    let returned: Maybe<bool> = preserve(value);
    let payload: bool = match (returned) { Some(inner) -> inner, None -> true };
    if (payload) { return 1; }
    return 0;
}
"#;
    let bytes = common::run_gpu_codegen_with_timeout("concrete enum return", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("compile concrete enum return");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("concrete enum return", "concrete_enum_return", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn option_bool_enum_methods_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/option_bool.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("Option<bool> enum methods", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile Option<bool> enum methods");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "Option<bool> enum methods",
            "option_bool_enum_methods",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn option_bool_method_results_pass_directly_to_imported_functions() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_option_bool_method_argument.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("imported enum method argument", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile imported enum method result as an argument");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported enum method argument",
            "option_bool_method_argument",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn option_bool_rejects_wrong_payload_and_receiver() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, body) in [
        (
            "payload",
            "let value: core::option::Option<bool> = core::option::Some(7);",
        ),
        (
            "receiver",
            "let value: core::option::Option<i32> = core::option::Some(7); let found: bool = value.contains(true);",
        ),
        (
            "method_result",
            "let value: core::option::Option<bool> = core::option::Some(false); let found: bool = core::result::contains(value.or(value), false);",
        ),
    ] {
        let entry = common::TempArtifact::new("laniusc_option_bool", name, Some("lani"));
        entry.write_str(&format!(
            "module app::main;\nimport core::option;\nimport core::result;\nfn main() -> i32 {{ {body} return 0; }}\n"
        ));
        let path = entry.path().to_path_buf();
        let stdlib = root.join("stdlib");
        let result =
            common::run_gpu_codegen_with_timeout("Option<bool> type rejection", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            });
        let error = match result {
            Err(error) => error,
            Ok(_) => panic!("{name}: wrong Option<bool> types compiled"),
        };
        let diagnostic = error.to_public_diagnostic();
        assert!(
            matches!(diagnostic.code.as_str(), "LNC0006" | "LNC0027"),
            "{name}: {error:?}"
        );
    }
}

#[test]
fn imported_option_bool_methods_reject_wrong_argument_types() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for name in ["fallback", "combinator"] {
        let entry = root.join(format!(
            "tests/fixtures/stdlib_foundation/repro_option_bool_method_wrong_{name}.lani"
        ));
        let stdlib = root.join("stdlib");
        let result =
            common::run_gpu_codegen_with_timeout("imported method argument rejection", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
            });
        let error = match result {
            Err(error) => error,
            Ok(_) => panic!("{name}: an invalid imported method argument compiled"),
        };
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{name}: {error:?}"
        );
    }
}

#[test]
fn imported_methods_validate_multiple_scalar_and_nominal_parameters() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/imported_method_parameters.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_method_parameters_root");
    let bytes =
        common::run_gpu_codegen_with_timeout("typed imported method parameters", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect("execute static and receiver methods with multiple typed arguments");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "typed imported method parameters",
            "imported_method_parameters",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;

    for (name, body) in [
        (
            "constructor_first",
            "let value: core::checker::Checker = core::checker::Checker::new(false, true);",
        ),
        (
            "constructor_second",
            "let value: core::checker::Checker = core::checker::Checker::new(7, 3);",
        ),
        (
            "method_first",
            "let found: bool = value.accepts(false, true);",
        ),
        ("method_second", "let found: bool = value.accepts(7, 3);"),
        (
            "method_third",
            "let selected: core::checker::Checker = value.choose(value, value, 3);",
        ),
        (
            "nominal",
            "let other: Other = Other { value: 7 }; let selected: core::checker::Checker = value.choose(other, value, true);",
        ),
        (
            "typed_receiver_scalar",
            "let found: i32 = value.biased(false, true);",
        ),
        (
            "typed_receiver_last",
            "let found: i32 = value.biased(3, 7);",
        ),
        (
            "typed_receiver_qualified",
            "let other: Other = Other { value: 7 }; let found: i32 = core::checker::Checker::biased(other, 3, true);",
        ),
    ] {
        let source = common::TempArtifact::new("laniusc_method_parameters", name, Some("lani"));
        source.write_str(&format!(
            "module app::main;\nimport core::checker;\nstruct Other {{ value: i32 }}\nfn main() -> i32 {{ let value: core::checker::Checker = core::checker::Checker::new(7, true); {body} return 0; }}\n"
        ));
        let path = source.path().to_path_buf();
        let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_method_parameters_root");
        let result =
            common::run_gpu_codegen_with_timeout("typed method argument rejection", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            });
        let error = match result {
            Err(error) => error,
            Ok(_) => panic!("{name}: a wrong imported method argument compiled"),
        };
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{name}: {error:?}"
        );
    }
}

#[test]
fn imported_empty_struct_results_execute_without_erasing_nominal_checks() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, stdlib_relative) in [
        (
            "repro_range_full_growth",
            "tests/fixtures/stdlib_foundation/repro_range_full_growth_root",
        ),
        ("repro_wide_range_full_import", "stdlib"),
    ] {
        let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let stdlib = root.join(stdlib_relative);
        let bytes =
            common::run_gpu_codegen_with_timeout("imported empty struct result", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
            })
            .expect("compile empty result after unrelated interface growth");
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output =
                common::run_x86_64_elf_output("imported empty struct result", name, &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert!(output.stdout.is_empty(), "{output:?}");
            assert!(output.stderr.is_empty(), "{output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
    for (name, body) in [
        (
            "wrong_nominal",
            "let wrong: Other = core::range::range_full();",
        ),
        (
            "wrong_scalar",
            "let wrong: i32 = core::range::range_full();",
        ),
    ] {
        let source = common::TempArtifact::new("laniusc_empty_struct", name, Some("lani"));
        source.write_str(&format!(
            "module app::main;\nimport core::range;\nstruct Other {{ value: i32 }}\nfn main() -> i32 {{ {body} return 0; }}\n"
        ));
        let path = source.path().to_path_buf();
        let stdlib = root.join("stdlib");
        let error =
            match common::run_gpu_codegen_with_timeout("empty result nominal checking", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            }) {
                Err(error) => error,
                Ok(_) => panic!("{name}: an empty struct was accepted as an unrelated type"),
            };
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{name}: {error:?}"
        );
    }
}

#[test]
fn imported_option_bool_factory_result_supports_method_calls() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_option_bool_factory_method.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("generic factory receiver", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile imported generic factory result as a receiver");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "generic factory receiver",
            "option_bool_factory_method",
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
fn imported_generic_factories_preserve_receiver_specializations() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_factory_receiver.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_factory_receiver_root");
    let bytes = common::run_gpu_codegen_with_timeout("concrete factory receivers", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("preserve concrete scalar arguments and select their method specializations");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "concrete factory receivers",
            "concrete_factory_receivers",
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
fn imported_generic_factory_methods_reject_wrong_result_types() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, body) in [
        (
            "byte_as_bool",
            "let byte: u8 = 255; let invalid: bool = core::factory::byte_value(byte).read();",
        ),
        (
            "bool_as_byte",
            "let invalid: u8 = core::factory::bool_value(false).read();",
        ),
    ] {
        let entry = common::TempArtifact::new("laniusc_factory_receiver", name, Some("lani"));
        entry.write_str(&format!(
            "module app::main;\nimport core::factory;\nfn main() -> i32 {{ {body} return 0; }}\n"
        ));
        let path = entry.path().to_path_buf();
        let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_factory_receiver_root");
        let result =
            common::run_gpu_codegen_with_timeout("factory specialization rejection", move || {
                pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
            });
        let error = match result {
            Err(error) => error,
            Ok(_) => panic!("{name}: a factory method result satisfied the wrong scalar type"),
        };
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{name}: {error:?}"
        );
    }
}

#[test]
fn four_argument_generic_factory_receiver_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_factory_quad_receiver.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_factory_receiver_root");
    let bytes = common::run_gpu_codegen_with_timeout("four-argument factory receiver", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile four scalar generic arguments and the five-word enum result");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("four-argument factory receiver", "quad_factory", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn mixed_generic_factories_execute_in_one_module() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_factory_mixed_receiver.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_factory_receiver_root");
    let bytes = common::run_gpu_codegen_with_timeout("mixed generic factories", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile both generic enum factory families in one module");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("mixed generic factories", "mixed_factories", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn later_generic_enums_preserve_payloads_and_empty_variants() {
    let source = r#"
pub enum Maybe<T> { Some(T), None }
pub enum Quad<A, B, C, D> { Empty, Item(A, B, C, D) }
fn preserve(value: Quad<bool, u8, i32, u32>) -> Quad<bool, u8, i32, u32> {
    return value;
}
fn main() -> i32 {
    let byte: u8 = 255;
    let signed: i32 = -7;
    let unsigned: u32 = 9;
    let value: Quad<bool, u8, i32, u32> = Item(false, byte, signed, unsigned);
    let returned: Quad<bool, u8, i32, u32> = preserve(value);
    let flag: bool = match (returned) {
        Empty -> true, Item(flag_value, flag_byte, flag_signed, flag_unsigned) -> flag_value
    };
    let zero_byte: u8 = 0;
    let actual_byte: u8 = match (returned) {
        Empty -> zero_byte, Item(byte_flag, byte_value, byte_signed, byte_unsigned) -> byte_value
    };
    let actual_signed: i32 = match (returned) {
        Empty -> 0, Item(signed_flag, signed_byte, signed_value, signed_unsigned) -> signed_value
    };
    let zero_unsigned: u32 = 0;
    let actual_unsigned: u32 = match (returned) {
        Empty -> zero_unsigned, Item(unsigned_flag, unsigned_byte, unsigned_signed, unsigned_value) -> unsigned_value
    };
    if (flag) { return 1; }
    if (actual_byte != byte) { return 2; }
    if (actual_signed != signed) { return 3; }
    if (actual_unsigned != unsigned) { return 4; }
    let empty: Quad<bool, u8, i32, u32> = Empty;
    let returned_empty: Quad<bool, u8, i32, u32> = preserve(empty);
    let is_empty: bool = match (returned_empty) {
        Empty -> true,
        Item(empty_flag, empty_byte, empty_signed, empty_unsigned) -> false
    };
    if (!is_empty) { return 5; }
    let first: Maybe<bool> = Some(true);
    let first_payload: bool = match (first) { Some(first_flag) -> first_flag, None -> false };
    if (!first_payload) { return 6; }
    return 0;
}
"#;
    let bytes = common::run_gpu_codegen_with_timeout("later generic enum layout", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("compile distinct generic enums with declaration-local discriminants");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "later generic enum layout",
            "later_generic_enum_layout",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn unused_generic_enum_does_not_prevent_later_construction() {
    let source = include_str!("fixtures/stdlib_foundation/repro_generic_enum_mixed_layout.lani");
    let bytes = common::run_gpu_codegen_with_timeout("unused generic enum layout", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("compile the nine-line mixed enum layout reproduction");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "unused generic enum layout",
            "unused_generic_enum_layout",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn enum_match_later_payload_comparison_executes_on_x86() {
    let source = include_str!("fixtures/stdlib_foundation/repro_enum_match_later_payload_arm.lani");
    let bytes = common::run_gpu_codegen_with_timeout("later payload match comparison", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("compile a scalar payload comparison in the second match arm");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "later payload match comparison",
            "enum_match_later_payload_comparison",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn enum_match_result_consumers_execute_on_x86() {
    let source = include_str!("fixtures/stdlib_foundation/enum_match_consumers.lani");
    let bytes = common::run_gpu_codegen_with_timeout("match result consumers", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("compile match results in locals, returns, and assignments");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("match result consumers", "enum_match_consumers", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn enum_match_payload_short_circuit_executes_on_x86() {
    for (name, source) in [
        (
            "logical payload reproduction",
            include_str!("fixtures/stdlib_foundation/repro_enum_match_logical_payload.lani"),
        ),
        (
            "logical payload cases",
            include_str!("fixtures/stdlib_foundation/enum_match_logical_cases.lani"),
        ),
    ] {
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
        })
        .expect("compile compound final arms with concrete and generic payloads");
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, "enum_match_logical_payload", &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert!(output.stdout.is_empty(), "{name}: {output:?}");
            assert!(output.stderr.is_empty(), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn boolean_programs_use_option_bool_enum_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, expected) in [
        ("vector_true_count", b"2\n".as_slice()),
        ("boolean_window_checksum", b"3\n".as_slice()),
    ] {
        let entry = root.join(format!("sample_programs/{name}.lani"));
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("Option<bool> program", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect("compile program using Option<bool>");
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output("Option<bool> program", name, &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert_eq!(output.stdout, expected, "{name}");
            assert!(output.stderr.is_empty(), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, expected);
    }
}
