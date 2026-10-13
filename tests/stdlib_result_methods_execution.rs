mod common;

use laniusc_compiler::compiler::{CompileError, compile_entry_to_x86_64_with_stdlib};

#[derive(Clone, Copy)]
struct Payload {
    kind: &'static str,
    values: [&'static str; 3],
    text: Option<[&'static str; 3]>,
}

const SIGNED: Payload = Payload {
    kind: "i32",
    values: ["0", "-2147483648", "2147483647"],
    text: None,
};
const UNSIGNED: Payload = Payload {
    kind: "u32",
    values: ["0", "4294967295", "2147483648"],
    text: None,
};
const BOOLEAN: Payload = Payload {
    kind: "bool",
    values: ["false", "true", "true"],
    text: None,
};
const FLOAT: Payload = Payload {
    kind: "f32",
    values: ["0.0", "-2.5", "7.5"],
    text: None,
};
const CHARACTER: Payload = Payload {
    kind: "char",
    values: ["'\\0'", "'Ω'", "'é'"],
    text: None,
};
const TEXT: Payload = Payload {
    kind: "str",
    values: ["\"\"", "\"payload Ω\"", "\"explicit fallback\""],
    text: Some(["", "payload Ω", "explicit fallback"]),
};

#[test]
fn result_generic_methods_execute_all_state_pairs_and_preserve_inputs() {
    for (name, success, error) in [
        ("signed bool", SIGNED, BOOLEAN),
        ("bool signed", BOOLEAN, SIGNED),
        ("unsigned bool", UNSIGNED, BOOLEAN),
        ("float char", FLOAT, CHARACTER),
        ("char float", CHARACTER, FLOAT),
        ("text bool", TEXT, BOOLEAN),
        ("bool text", BOOLEAN, TEXT),
        ("text text", TEXT, TEXT),
        ("unsigned unsigned", UNSIGNED, UNSIGNED),
    ] {
        let result_type = format!("core::result::Result<{}, {}>", success.kind, error.kind);
        let mut source = String::from(
            "module app::main;\nimport core::result;\nimport std::io;\nfn main() -> i32 {\n",
        );
        for (prefix, payload) in [("value", success), ("error", error)] {
            for (suffix, literal) in ["zero", "other", "fallback"]
                .into_iter()
                .zip(payload.values)
            {
                source.push_str(&format!(
                    "    let {prefix}_{suffix}: {} = {literal};\n",
                    payload.kind
                ));
            }
        }
        let states = [
            ("ok_zero", Ok(0)),
            ("ok_other", Ok(1)),
            ("err_zero", Err(0)),
            ("err_other", Err(1)),
        ];
        let names = ["zero", "other", "fallback"];
        for (state, value) in states {
            let (variant, prefix, index) = match value {
                Ok(index) => ("Ok", "value", index),
                Err(index) => ("Err", "error", index),
            };
            source.push_str(&format!(
                "    let {state}: {result_type} = core::result::{variant}({prefix}_{});\n",
                names[index]
            ));
        }
        let mut stdout = String::new();
        let mut failure = 1;
        for (state, value) in states {
            assert_payload(
                &mut source,
                &mut stdout,
                &mut failure,
                success,
                "value",
                value.unwrap_or(2),
                &format!("{state}.unwrap_or(value_fallback)"),
            );
            for expression in [
                format!("{state}.unwrap_err_or(error_fallback)"),
                format!("core::result::unwrap_err_or({state}, error_fallback)"),
            ] {
                assert_payload(
                    &mut source,
                    &mut stdout,
                    &mut failure,
                    error,
                    "error",
                    value.err().unwrap_or(2),
                    &expression,
                );
            }
        }
        for (left, left_value) in states {
            for (right, right_value) in states {
                for (method, expected) in [
                    ("or", left_value.or(right_value)),
                    ("and", left_value.and(right_value)),
                ] {
                    let selected = format!("selected_{failure}");
                    source.push_str(&format!(
                        "    let {selected}: {result_type} = {left}.{method}({right});\n"
                    ));
                    assert_result(
                        &mut source,
                        &mut stdout,
                        &mut failure,
                        success,
                        error,
                        &selected,
                        expected,
                    );
                }
            }
        }
        // Combinators borrow both inputs; verify the original tag and payload afterwards.
        for (state, expected) in states {
            assert_result(
                &mut source,
                &mut stdout,
                &mut failure,
                success,
                error,
                state,
                expected,
            );
        }
        source.push_str("    return 0;\n}\n");
        let bytes = compile_source(name, &source).expect("compile shared Result receiver bodies");
        assert_native_output(name, &bytes, stdout.as_bytes());
    }
}

#[test]
fn result_generic_methods_bind_both_type_parameters_to_the_receiver() {
    for statement in [
        "let found: i32 = primary.unwrap_or(false);",
        "let found: str = primary.unwrap_err_or(7);",
        "let found: str = core::result::unwrap_err_or(primary, false);",
        "let found: i32 = primary.unwrap_err_or(\"fallback\");",
        "let found: core::result::Result<i32, str> = primary.or(wrong_success);",
        "let found: core::result::Result<i32, str> = primary.or(wrong_error);",
        "let found: core::result::Result<i32, str> = primary.and(wrong_success);",
        "let found: core::result::Result<i32, str> = primary.and(wrong_error);",
    ] {
        let source = format!(
            r#"
module app::main;
import core::result;
fn main() -> i32 {{
    let primary: core::result::Result<i32, str> = core::result::Ok(-7);
    let wrong_success: core::result::Result<bool, str> = core::result::Ok(false);
    let wrong_error: core::result::Result<i32, bool> = core::result::Err(false);
    {statement}
    return 0;
}}
"#
        );
        let error = match compile_source("wrong Result method argument", &source) {
            Err(error) => error,
            Ok(_) => panic!("Result accepted an inconsistent parameter: {statement}"),
        };
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{statement}: {error:?}"
        );
    }
}

#[test]
fn result_generic_methods_preserve_nan_and_negative_zero_in_either_payload() {
    let source = r#"
module app::main;
import core::result;
fn main() -> i32 {
    let zero: f32 = 0.0;
    let nan: f32 = zero / zero;
    let negative_zero: f32 = -zero;
    let successful: core::result::Result<f32, char> = core::result::Ok(nan);
    let failed: core::result::Result<f32, char> = core::result::Err('Ω');
    let error_nan: core::result::Result<char, f32> = core::result::Err(nan);
    let character: core::result::Result<char, f32> = core::result::Ok('é');
    let selected: core::result::Result<f32, char> = successful.or(failed);
    let chained: core::result::Result<f32, char> = successful.and(successful);
    let selected_error: core::result::Result<char, f32> = error_nan.and(character);
    let fallback_error: core::result::Result<char, f32> = error_nan.or(error_nan);
    let a: f32 = selected.unwrap_or(7.5);
    let b: f32 = chained.unwrap_or(7.5);
    let c: f32 = selected_error.unwrap_err_or(7.5);
    let d: f32 = fallback_error.unwrap_err_or(7.5);
    let e: f32 = core::result::unwrap_err_or(error_nan, 7.5);
    if (a == a || b == b || c == c || d == d || e == e) { return 1; }
    if (successful.unwrap_err_or('A') != 'A' || failed.unwrap_err_or('A') != 'Ω') { return 2; }
    let stored_zero: core::result::Result<f32, bool> = core::result::Ok(negative_zero);
    let failed_zero: core::result::Result<bool, f32> = core::result::Err(negative_zero);
    if (!(1.0 / stored_zero.unwrap_or(7.5) < zero)) { return 3; }
    if (!(1.0 / failed_zero.unwrap_err_or(7.5) < zero)) { return 4; }
    if (!(1.0 / core::result::unwrap_err_or(failed_zero, 7.5) < zero)) { return 5; }
    return 0;
}
"#;
    let bytes = compile_source("Result special float payloads", source)
        .expect("compile distinct success/error generic scalar slots");
    assert_native_output("Result special float payloads", &bytes, b"");
}

#[allow(clippy::too_many_arguments)]
fn assert_result(
    source: &mut String,
    stdout: &mut String,
    failure: &mut usize,
    success: Payload,
    error: Payload,
    value: &str,
    expected: Result<usize, usize>,
) {
    let (tag, other_tag, payload, prefix, index, extraction) = match expected {
        Ok(index) => ("is_ok", "is_err", success, "value", index, "unwrap_or"),
        Err(index) => ("is_err", "is_ok", error, "error", index, "unwrap_err_or"),
    };
    source.push_str(&format!(
        "    if (!{value}.{tag}() || {value}.{other_tag}()) {{ return {failure}; }}\n"
    ));
    assert_payload(
        source,
        stdout,
        failure,
        payload,
        prefix,
        index,
        &format!("{value}.{extraction}({prefix}_fallback)"),
    );
}

#[allow(clippy::too_many_arguments)]
fn assert_payload(
    source: &mut String,
    stdout: &mut String,
    failure: &mut usize,
    payload: Payload,
    prefix: &str,
    index: usize,
    expression: &str,
) {
    let variable = format!("recovered_{failure}");
    source.push_str(&format!(
        "    let {variable}: {} = {expression};\n",
        payload.kind
    ));
    if let Some(text) = payload.text {
        source.push_str(&format!(
            "    if (std::io::println({variable}) != {}) {{ return {failure}; }}\n",
            text[index].len() + 1
        ));
        stdout.push_str(text[index]);
        stdout.push('\n');
    } else {
        let suffix = ["zero", "other", "fallback"][index];
        source.push_str(&format!(
            "    if ({variable} != {prefix}_{suffix}) {{ return {failure}; }}\n"
        ));
    }
    *failure += 1;
}

fn compile_source(label: &str, source: &str) -> Result<Vec<u8>, CompileError> {
    let entry = common::TempArtifact::new("result_methods", label, Some("lani"));
    entry.write_str(source);
    let path = entry.path().to_path_buf();
    let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
    })
}

fn assert_native_output(label: &str, bytes: &[u8], stdout: &[u8]) {
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(label, "result_methods", bytes);
        assert_eq!(output.status.code(), Some(0), "{label}: {output:?}");
        assert_eq!(output.stdout, stdout, "{label}: {output:?}");
        assert!(output.stderr.is_empty(), "{label}: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (label, bytes, stdout);
}
