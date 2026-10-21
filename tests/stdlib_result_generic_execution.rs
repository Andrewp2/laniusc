mod common;

use laniusc_compiler::compiler::{CompileError, compile_entry_to_x86_64_with_stdlib};

#[test]
fn actual_result_module_predicates_and_membership_execute() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/result_generic_import.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("actual Result module", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile the complete Result source module through the actual stdlib root");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("actual Result module", "result_generic", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn result_reading_total_program_executes_both_concrete_return_variants() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/result_reading_total.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("Result reading total", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile a real program using concrete Result returns and several stdlib modules");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("Result reading total", "result_reading_total", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"20\n-2\n", "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn result_predicates_and_matches_preserve_borrowed_descriptors() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/result_descriptor_payloads.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("Result descriptors", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("preserve string and borrowed slice descriptors through both Result variants");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("Result descriptors", "result_generic", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"rejected\n\n", "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn result_slice_payloads_keep_native_bounds() {
    for (label, access) in [
        ("Result populated bounds", "recovered[3]"),
        ("Result empty bounds", "recovered_empty[0]"),
    ] {
        let source = include_str!("fixtures/stdlib_foundation/result_descriptor_payloads.lani")
            .replace("    return 0;", &format!("    return {access};"));
        let bytes = compile_source(label, &source)
            .expect("bounds metadata must survive Result slice extraction");
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(label, "result_generic", &bytes);
            assert_eq!(output.status.code(), Some(101), "{label}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn result_slice_arguments_preserve_generic_and_concrete_type_relations() {
    for (label, left_type, right_type, left_value, right_value, expression) in [
        (
            "repeated successful slice type",
            "[i32], str",
            "[u8], str",
            "view",
            "bytes",
            "core::result::or(left, right)",
        ),
        (
            "repeated failed slice type",
            "str, [i32]",
            "str, [u8]",
            "\"left\"",
            "\"right\"",
            "core::result::and(left, right)",
        ),
        (
            "concrete successful scalar type",
            "[i32], str",
            "[i32], str",
            "view",
            "view",
            "core::result::contains(left, 7)",
        ),
    ] {
        let source = format!(
            r#"
module app::main;
import core::result;
fn exercise(view: [i32], bytes: [u8]) -> i32 {{
    let left: core::result::Result<{left_type}> = core::result::Ok({left_value});
    let right: core::result::Result<{right_type}> = core::result::Ok({right_value});
    {expression}; return 0;
}}
fn main() -> i32 {{
    let values: [i32; 3] = [4, 7, -9];
    let one: u8 = 1; let two: u8 = 2; let three: u8 = 3;
    let bytes: [u8; 3] = [one, two, three];
    return exercise(values, bytes);
}}
"#
        );
        let error = compile_source(label, &source)
            .expect_err("compound generic arguments must keep their checked type relations");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{label}: {error:?}"
        );
    }
}

#[test]
fn result_scalar_payload_functions_execute_both_variants() {
    let source = r#"
module app::main;
import core::result;
fn main() -> i32 {
    let success: core::result::Result<i32, bool> = core::result::Ok(-7);
    let failure: core::result::Result<i32, bool> = core::result::Err(false);
    let zero: core::result::Result<i32, bool> = core::result::Ok(0);
    let low: core::result::Result<i32, bool> = core::result::Ok(-2147483648);
    let high: core::result::Result<i32, bool> = core::result::Ok(2147483647);
    if (core::result::unwrap_or(success, 99) != -7) { return 1; }
    if (core::result::unwrap_or(failure, 99) != 99) { return 2; }
    if (core::result::unwrap_or(zero, 99) != 0) { return 3; }
    if (core::result::unwrap_or(low, 99) != -2147483648) { return 4; }
    if (core::result::unwrap_or(high, 99) != 2147483647) { return 5; }
    let preferred: core::result::Result<i32, bool> = core::result::or(success, failure);
    let fallback: core::result::Result<i32, bool> = core::result::or(failure, success);
    let both_errors: core::result::Result<i32, bool> = core::result::or(failure, failure);
    if (!core::result::contains(preferred, -7)) { return 6; }
    if (!core::result::contains(fallback, -7)) { return 7; }
    if (!core::result::contains_err(both_errors, false)) { return 8; }
    let next: core::result::Result<i32, bool> = core::result::and(success, zero);
    let next_error: core::result::Result<i32, bool> = core::result::and(success, failure);
    let first_error: core::result::Result<i32, bool> = core::result::and(failure, success);
    if (!core::result::contains(next, 0)) { return 9; }
    if (!core::result::contains_err(next_error, false)) { return 10; }
    if (!core::result::contains_err(first_error, false)) { return 11; }
    let boolean: core::result::Result<bool, i32> = core::result::Ok(false);
    let error_zero: core::result::Result<bool, i32> = core::result::Err(0);
    if (core::result::unwrap_or(boolean, true)) { return 12; }
    if (!core::result::unwrap_or(error_zero, true)) { return 13; }
    let reverse_or: core::result::Result<bool, i32> = core::result::or(error_zero, boolean);
    let reverse_and: core::result::Result<bool, i32> = core::result::and(boolean, error_zero);
    if (!core::result::contains(reverse_or, false)) { return 14; }
    if (!core::result::contains_err(reverse_and, 0)) { return 15; }
    if (!core::result::contains(success, -7)) { return 16; }
    if (!core::result::contains_err(failure, false)) { return 17; }
    if (!core::result::contains(boolean, false)) { return 18; }
    if (!core::result::contains_err(error_zero, 0)) { return 19; }
    return 0;
}
"#;
    let bytes = compile_source("Result concrete body specialization", source)
        .expect("specialize both ordered scalar type environments through the actual stdlib");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("Result scalar payloads", "result_generic", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn result_payload_functions_preserve_float_char_unsigned_and_string_values() {
    let source = r#"
module app::main;
import core::result;
import std::io;
fn main() -> i32 {
    let high: u32 = 4294967295;
    let zero: u32 = 0;
    let unsigned: core::result::Result<u32, bool> = core::result::Ok(high);
    let unsigned_error: core::result::Result<u32, bool> = core::result::Err(false);
    let unsigned_or: core::result::Result<u32, bool> = core::result::or(unsigned_error, unsigned);
    let unsigned_and: core::result::Result<u32, bool> = core::result::and(unsigned, unsigned);
    if (core::result::unwrap_or(unsigned_or, zero) != high || core::result::unwrap_or(unsigned_and, zero) != high) { return 1; }
    if (core::result::unwrap_or(unsigned_error, high) != high) { return 2; }

    let floating: core::result::Result<f32, char> = core::result::Ok(-2.5);
    let float_error: core::result::Result<f32, char> = core::result::Err('Ω');
    let float_or: core::result::Result<f32, char> = core::result::or(float_error, floating);
    let float_and: core::result::Result<f32, char> = core::result::and(floating, floating);
    if (core::result::unwrap_or(float_or, 99.0) != -2.5 || core::result::unwrap_or(float_and, 99.0) != -2.5) { return 3; }
    if (core::result::unwrap_or(float_error, -7.5) != -7.5) { return 4; }
    let signed_zero: core::result::Result<f32, char> = core::result::Ok(-0.0);
    let negative_zero: f32 = core::result::unwrap_or(signed_zero, 99.0);
    if (negative_zero != 0.0 || 1.0 / negative_zero >= 0.0) { return 5; }
    let letter: core::result::Result<char, f32> = core::result::Ok('Ω');
    let letter_error: core::result::Result<char, f32> = core::result::Err(-2.5);
    let char_or: core::result::Result<char, f32> = core::result::or(letter_error, letter);
    let char_and: core::result::Result<char, f32> = core::result::and(letter, letter);
    if (core::result::unwrap_or(char_or, '\0') != 'Ω' || core::result::unwrap_or(char_and, '\0') != 'Ω') { return 6; }
    if (core::result::unwrap_or(letter_error, '\0') != '\0') { return 7; }

    let text: core::result::Result<str, bool> = core::result::Ok("payload");
    let text_error: core::result::Result<str, bool> = core::result::Err(false);
    let empty: core::result::Result<str, bool> = core::result::Ok("");
    let text_or: core::result::Result<str, bool> = core::result::or(text_error, text);
    let text_and: core::result::Result<str, bool> = core::result::and(text, text_error);
    let present_text: str = core::result::unwrap_or(text_or, "missing");
    let fallback_text: str = core::result::unwrap_or(text_and, "fallback");
    let empty_text: str = core::result::unwrap_or(empty, "missing");
    if (std::io::println(present_text) != 8 || std::io::println(fallback_text) != 9 || std::io::println(empty_text) != 1) { return 8; }

    let first_error: core::result::Result<bool, str> = core::result::Err("first");
    let second_error: core::result::Result<bool, str> = core::result::Err("second");
    let error_or: core::result::Result<bool, str> = core::result::or(first_error, second_error);
    let error_and: core::result::Result<bool, str> = core::result::and(first_error, second_error);
    let from_or: str = match (error_or) { core::result::Ok(_) -> "unexpected", core::result::Err(error) -> error };
    let from_and: str = match (error_and) { core::result::Ok(_) -> "unexpected", core::result::Err(error) -> error };
    if (std::io::println(from_or) != 7 || std::io::println(from_and) != 6) { return 9; }
    if (!core::result::unwrap_or(first_error, true) || !text.is_ok() || !empty.is_ok()) { return 10; }
    return 0;
}
"#;
    let bytes = compile_source("Result scalar and string specialization", source).expect(
        "instantiate scalar and string payloads without losing their machine representation",
    );
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "Result scalar and string payloads",
            "result_generic",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(
            output.stdout, b"payload\nfallback\n\nsecond\nfirst\n",
            "{output:?}"
        );
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn result_slice_payload_functions_execute_both_branches_and_preserve_aliases() {
    let source = r#"
module app::main;
import core::result;
import core::mem;
fn main() -> i32 {
    let backing: [i32; 2] = [-7, 99];
    let fallback_backing: [i32; 1] = [42];
    let view: [i32] = core::mem::i32_slice_from_raw_parts(core::mem::i32_array_data_ptr(backing), 2);
    let fallback: [i32] = core::mem::i32_slice_from_raw_parts(core::mem::i32_array_data_ptr(fallback_backing), 1);
    let success: core::result::Result<[i32], bool> = core::result::Ok(view);
    let failure: core::result::Result<[i32], bool> = core::result::Err(false);
    let recovered: [i32] = core::result::unwrap_or(success, fallback);
    let selected: [i32] = failure.unwrap_or(fallback);
    if (recovered[0] != -7 || recovered[1] != 99 || selected[0] != 42) { return 1; }
    recovered[1] = 23;
    selected[0] = 31;
    if (backing[1] != 23 || fallback_backing[0] != 31) { return 2; }
    let count: i32 = 0;
    for value in recovered { count += 1; }
    if (count != 2) { return 3; }
    count = 0;
    for value in selected { count += 1; }
    if (count != 1) { return 4; }
    return 0;
}
"#;
    let bytes = compile_source("Result slice specialization", source)
        .expect("compile complete Result slice payload bodies");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("Result slice specialization", "result_generic", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn result_membership_rejects_wrong_scalar_argument_types() {
    for expression in [
        "core::result::contains(success, false)",
        "core::result::contains_err(failure, 7)",
    ] {
        let source = format!(
            "module app::main; import core::result; fn main() -> i32 {{\n\
             let success: core::result::Result<i32, bool> = core::result::Ok(-7);\n\
             let failure: core::result::Result<i32, bool> = core::result::Err(false);\n\
             if ({expression}) {{ return 1; }} return 0; }}"
        );
        let error = compile_source("wrong Result membership argument", &source)
            .expect_err("membership compares the concrete payload type");
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{expression}: {error:?}"
        );
    }
}

fn compile_source(label: &str, source: &str) -> Result<Vec<u8>, CompileError> {
    let entry = common::TempArtifact::new("result_generic", label, Some("lani"));
    entry.write_str(source);
    let entry_path = entry.path().to_path_buf();
    let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry_path, &stdlib))
    })
}
