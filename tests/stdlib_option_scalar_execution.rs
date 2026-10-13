mod common;

use laniusc_compiler::compiler::{CompileError, compile_entry_to_x86_64_with_stdlib};

#[test]
fn option_scalar_payload_methods_execute_all_state_pairs() {
    for (name, element, zero, other, distinct, fallback) in [
        ("signed", "i32", "0", "-2147483648", "2147483647", "-7"),
        ("unsigned", "u32", "0", "4294967295", "2147483648", "1"),
        ("byte", "u8", "0", "255", "128", "1"),
        ("float", "f32", "0.0", "-2.5", "3.5", "1.5"),
        ("character", "char", "'\\0'", "'é'", "'Ω'", "'A'"),
    ] {
        let mut source = format!(
            r#"
module app::main;
import core::option;
fn main() -> i32 {{
    let zero: {element} = {zero};
    let other: {element} = {other};
    let distinct: {element} = {distinct};
    let fallback: {element} = {fallback};
    let absent: core::option::Option<{element}> = core::option::None();
    let stored_zero: core::option::Option<{element}> = core::option::Some(zero);
    let stored_other: core::option::Option<{element}> = core::option::Some(other);
    let stored_distinct: core::option::Option<{element}> = core::option::Some(distinct);
    if (!absent.is_none() || absent.is_some() || absent.contains(zero)) {{ return 1; }}
    if (!stored_zero.is_some() || stored_zero.is_none() || !stored_zero.contains(zero)) {{ return 2; }}
    if (!stored_other.contains(other) || stored_other.contains(distinct)) {{ return 3; }}
    if (absent.unwrap_or(fallback) != fallback || stored_zero.unwrap_or(fallback) != zero ||
        stored_other.unwrap_or(fallback) != other ||
        !stored_distinct.contains(distinct) || stored_distinct.unwrap_or(fallback) != distinct) {{ return 4; }}
"#
        );
        let states = [
            ("absent", None),
            ("stored_zero", Some("zero")),
            ("stored_other", Some("other")),
            ("stored_distinct", Some("distinct")),
        ];
        let mut failure = 5;
        for (left, left_payload) in states {
            for (right, right_payload) in states {
                for (method, expected) in [
                    ("or", left_payload.or(right_payload)),
                    ("and", left_payload.and(right_payload)),
                    ("xor", left_payload.xor(right_payload)),
                ] {
                    let variable = format!("selected_{failure}");
                    source.push_str(&format!(
                        "    let {variable}: core::option::Option<{element}> = {left}.{method}({right});\n"
                    ));
                    if let Some(payload) = expected {
                        source.push_str(&format!(
                            "    if (!{variable}.is_some() || !{variable}.contains({payload}) || {variable}.unwrap_or(fallback) != {payload}) {{ return {failure}; }}\n"
                        ));
                    } else {
                        source.push_str(&format!(
                            "    if (!{variable}.is_none() || {variable}.contains(zero) || {variable}.unwrap_or(fallback) != fallback) {{ return {failure}; }}\n"
                        ));
                    }
                    failure += 1;
                }
            }
        }
        source.push_str("    if (!absent.is_none() || !stored_zero.contains(zero) || !stored_other.contains(other) || !stored_distinct.contains(distinct)) { return 60; }\n    return 0;\n}\n");
        let bytes =
            compile_stdlib_source(name, &source).expect("compile concrete Option scalar methods");
        assert_native_exit(name, &bytes);
    }
}

#[test]
fn option_float_methods_preserve_nan_payloads_and_ieee_membership() {
    let source = r#"
module app::main;
import core::option;
fn main() -> i32 {
    let zero: f32 = 0.0;
    let nan: f32 = zero / zero;
    let fallback: f32 = 7.5;
    let stored: core::option::Option<f32> = core::option::Some(nan);
    let absent: core::option::Option<f32> = core::option::None();
    if (!stored.is_some() || stored.contains(nan) || stored.contains(zero)) { return 1; }
    let recovered: f32 = stored.unwrap_or(fallback);
    if (recovered == recovered || absent.unwrap_or(fallback) != fallback) { return 2; }
    let selected: core::option::Option<f32> = stored.or(absent);
    let selected_value: f32 = selected.unwrap_or(fallback);
    if (!selected.is_some() || selected_value == selected_value) { return 3; }
    let xor: core::option::Option<f32> = absent.xor(stored);
    let xor_value: f32 = xor.unwrap_or(fallback);
    if (!xor.is_some() || xor_value == xor_value) { return 4; }
    if (!stored.xor(stored).is_none() || !stored.and(absent).is_none()) { return 5; }
    let selected_and: core::option::Option<f32> = stored.and(stored);
    let and_value: f32 = selected_and.unwrap_or(fallback);
    if (!selected_and.is_some() || and_value == and_value) { return 6; }
    let negative_zero: f32 = -zero;
    let stored_zero: core::option::Option<f32> = core::option::Some(negative_zero);
    let reciprocal: f32 = 1.0 / stored_zero.unwrap_or(fallback);
    if (!(reciprocal < zero)) { return 7; }
    return 0;
}
"#;
    let bytes =
        compile_stdlib_source("Option float NaN", source).expect("compile Option NaN methods");
    assert_native_exit("Option float NaN", &bytes);
}

#[test]
fn option_scalar_methods_reject_wrong_payload_arguments() {
    for body in [
        "let value: core::option::Option<i32> = core::option::Some(7); let found: bool = value.contains(true);",
        "let value: core::option::Option<u32> = core::option::Some(7); let found: u32 = value.unwrap_or(false);",
        "let value: core::option::Option<i32> = core::option::Some(7); let wrong: core::option::Option<bool> = core::option::Some(true); let found: core::option::Option<i32> = value.or(wrong);",
        "let value: core::option::Option<f32> = core::option::Some(1.5); let wrong: core::option::Option<i32> = core::option::Some(7); let found: core::option::Option<f32> = value.and(wrong);",
        "let value: core::option::Option<char> = core::option::Some('é'); let wrong: core::option::Option<bool> = core::option::Some(false); let found: core::option::Option<char> = value.xor(wrong);",
    ] {
        let source = format!(
            "module app::main;\nimport core::option;\nfn main() -> i32 {{ {body} return 0; }}\n"
        );
        let error = compile_stdlib_source("Option wrong argument", &source)
            .expect_err("concrete payload methods must retain their argument types");
        assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
    }
}

#[test]
fn option_scalar_choice_program_executes() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/first_valid_reading.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("first valid reading", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile scalar Option choice with ranges, slices, and arithmetic");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("first valid reading", "first_valid_reading", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"-2\n5\n", "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

fn compile_stdlib_source(name: &str, source: &str) -> Result<Vec<u8>, CompileError> {
    let entry = common::TempArtifact::new("laniusc_option_scalar", "entry", Some("lani"));
    entry.write_str(source);
    let path = entry.path().to_path_buf();
    let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
    })
}

fn assert_native_exit(name: &str, bytes: &[u8]) {
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(name, "option_scalar", bytes);
        assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (name, bytes);
}
