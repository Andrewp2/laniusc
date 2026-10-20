mod common;

use laniusc_compiler::compiler::{CompileError, compile_entry_to_x86_64_with_stdlib};

#[test]
fn generic_slice_access_and_copying_execute_for_supported_scalar_types() {
    for (name, element, zero, other, fallback) in [
        ("signed", "i32", "0", "-2147483648", "2147483647"),
        ("unsigned", "u32", "0", "4294967295", "2147483648"),
        ("boolean", "bool", "false", "true", "true"),
        ("float", "f32", "0.0", "-2.5", "7.5"),
        ("character", "char", "'\\0'", "'Ω'", "'é'"),
        ("signed byte", "i8", "0", "-128", "127"),
        ("signed halfword", "i16", "0", "-32768", "32767"),
        ("unsigned byte", "u8", "0", "255", "128"),
        ("unsigned halfword", "u16", "0", "65535", "32768"),
    ] {
        let source = format!(
            r#"
module app::main;
import core::slice;
fn exercise(values: [{element}], source: [{element}]) -> i32 {{
    let zero: {element} = {zero};
    let other: {element} = {other};
    let fallback: {element} = {fallback};
    if (core::slice::first(values) != zero || core::slice::first_or(values, 3, fallback) != zero) {{ return 1; }}
    if (core::slice::get_or(values, 3, 1, fallback) != other) {{ return 2; }}
    if (core::slice::first_or(values, 0, fallback) != fallback || core::slice::first_or(values, -1, fallback) != fallback) {{ return 3; }}
    if (core::slice::get_or(values, 3, -1, fallback) != fallback || core::slice::get_or(values, 3, 3, fallback) != fallback ||
        core::slice::get_or(values, -1, 0, fallback) != fallback) {{ return 4; }}
    if (!core::slice::set(values, 3, 0, other) || values[0] != other ||
        core::slice::first(values) != other || core::slice::first_or(values, 3, fallback) != other) {{ return 5; }}
    if (core::slice::set(values, 3, -1, zero) || core::slice::set(values, 3, 3, zero) || values[0] != other) {{ return 6; }}
    if (!core::slice::swap(values, 3, 0, 2) || values[0] != fallback || values[2] != other) {{ return 7; }}
    if (core::slice::swap(values, 3, -1, 0) || core::slice::swap(values, 3, 0, 3) ||
        !core::slice::swap(values, 3, 0, 0) || values[0] != fallback) {{ return 8; }}
    if (core::slice::fill(values, -1, zero) != 0 || core::slice::fill(values, 0, zero) != 0 || values[0] != fallback) {{ return 9; }}
    if (core::slice::fill(values, 2, zero) != 2 || values[0] != zero || values[1] != zero || values[2] != other) {{ return 10; }}
    if (core::slice::reverse_in_place(values, 3) != 1 || values[0] != other || values[2] != zero) {{ return 11; }}
    if (core::slice::reverse_in_place(values, -1) != 0 || core::slice::reverse_in_place(values, 0) != 0 ||
        core::slice::reverse_in_place(values, 1) != 0 || values[0] != other) {{ return 12; }}
    if (!core::slice::copy_within(values, 3, 0, 2, 1) || values[0] != other || values[1] != other || values[2] != zero) {{ return 13; }}
    if (!core::slice::copy_within(values, 3, 1, 3, 0) || values[0] != other || values[1] != zero || values[2] != zero) {{ return 14; }}
    if (core::slice::copy_within(values, -1, 0, 0, 0) || core::slice::copy_within(values, 3, 0, 2, 2) ||
        core::slice::copy_within(values, 3, 2, 1, 0) || values[0] != other || values[1] != zero) {{ return 15; }}
    if (!core::slice::copy_within(values, 3, 3, 3, 3)) {{ return 16; }}
    if (!core::slice::copy_nonoverlapping_prefix(values, 3, source, 3) ||
        values[0] != fallback || values[1] != zero || values[2] != other) {{ return 17; }}
    if (core::slice::copy_nonoverlapping_prefix(values, 3, source, 4) ||
        core::slice::copy_nonoverlapping_prefix(values, -1, source, 1) || values[0] != fallback) {{ return 18; }}
    if (!core::slice::copy_nonoverlapping_prefix(values, 0, source, 0)) {{ return 19; }}
    if (!core::slice::copy_nonoverlapping_range(values, 3, 1, source, 3, 0, 2) ||
        values[0] != fallback || values[1] != fallback || values[2] != zero) {{ return 20; }}
    if (core::slice::copy_nonoverlapping_range(values, 3, 2, source, 3, 0, 2) ||
        core::slice::copy_nonoverlapping_range(values, 3, 0, source, 3, 2, 2) ||
        core::slice::copy_nonoverlapping_range(values, 3, -1, source, 3, 0, 0) ||
        core::slice::copy_nonoverlapping_range(values, 3, 0, source, 3, 0, -1) ||
        values[0] != fallback || values[1] != fallback || values[2] != zero) {{ return 21; }}
    if (!core::slice::copy_nonoverlapping_range(values, 3, 3, source, 3, 3, 0)) {{ return 22; }}
    if (source[0] != fallback || source[1] != zero || source[2] != other) {{ return 23; }}
    return 0;
}}
fn main() -> i32 {{
    let zero: {element} = {zero};
    let other: {element} = {other};
    let fallback: {element} = {fallback};
    let backing: [{element}; 3] = [zero, other, fallback];
    let source: [{element}; 3] = [fallback, zero, other];
    return exercise(backing, source);
}}
"#
        );
        let bytes = compile_source(name, &source).expect("compile actual generic slice APIs");
        assert_native_exit(name, &bytes, 0);
    }
}

#[test]
fn generic_slice_string_elements_preserve_pointer_and_length() {
    let source = include_str!("fixtures/stdlib_foundation/repro_generic_slice_string_elements.lani");
    let bytes = compile_source("generic string slice element", source)
        .expect("compile generic string element extraction");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("generic string slice element", "slice_generic", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, "Ω\n".as_bytes(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn generic_slice_arguments_preserve_element_type_relations() {
    for statement in [
        "let found: i32 = core::slice::get_or(values, 3, 0, false);",
        "let found: bool = core::slice::set(values, 3, 0, false);",
        "let written: i32 = core::slice::fill(values, 3, false);",
        "core::slice::copy_nonoverlapping_prefix(values, 3, wrong, 3);",
        "core::slice::copy_nonoverlapping_range(values, 3, 0, wrong, 3, 0, 3);",
    ] {
        let source = format!(
            "module app::main; import core::slice; fn main() -> i32 {{\n\
             let values: [i32; 3] = [-7, 0, 99];\n\
             let wrong: [bool; 3] = [false, true, false];\n\
             {statement} return 0; }}"
        );
        let error = match compile_source("wrong generic slice element", &source) {
            Err(error) => error,
            Ok(_) => panic!("generic slice accepted different element types: {statement}"),
        };
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{statement}: {error:?}"
        );
    }
}

#[test]
fn generic_slice_raw_storage_keeps_checked_element_types() {
    let source = include_str!("fixtures/stdlib_foundation/repro_generic_slice_raw_view.lani");
    let bytes = compile_source("generic raw slice", source)
        .expect("typed raw views must infer scalar slice parameters");
    assert_native_exit("generic raw slice", &bytes, 0);
    for statement in [
        "core::slice::set(raw, 3, 0, false);",
        "core::slice::copy_nonoverlapping_prefix(raw, 3, wrong, 3);",
        "core::slice::copy_nonoverlapping_prefix(wrong, 3, raw, 3);",
    ] {
        let source = format!(
            "module app::main; import core::slice; import core::mem; fn main() -> i32 {{\n\
             let values: [i32; 3] = [-7, 0, 99];\n\
             let raw: [i32] = core::mem::i32_slice_from_raw_parts(core::mem::i32_array_data_ptr(values), 3);\n\
             let wrong: [bool; 3] = [false, true, false];\n\
             {statement} return 0; }}"
        );
        let error = match compile_source("wrong raw slice element", &source) {
            Err(error) => error,
            Ok(_) => panic!("raw view erased the element constraint: {statement}"),
        };
        assert_eq!(
            error.to_public_diagnostic().code,
            "LNC0006",
            "{statement}: {error:?}"
        );
    }
}

#[test]
fn generic_slice_lengths_reject_boolean_fields() {
    let source = r#"
module app::main;
import core::slice;
struct Flags { length: bool }
fn main() -> i32 {
    let values: [i32; 2] = [3, 7];
    let flags: Flags = Flags { length: true };
    return core::slice::reverse_in_place(values, flags.length);
}
"#;
    let error = match compile_source("invalid member slice length", source) {
        Err(error) => error,
        Ok(_) => panic!("a Boolean field cannot supply an integer slice length"),
    };
    assert_eq!(error.to_public_diagnostic().code, "LNC0006", "{error:?}");
}

#[test]
fn generic_slice_copying_preserves_nan_and_negative_zero() {
    let source = r#"
module app::main;
import core::slice;
fn exercise(values: [f32], output: [f32]) -> i32 {
    let nan: f32 = 0.0 / 0.0;
    let negative_zero: f32 = -0.0;
    if (!core::slice::set(values, 3, 0, nan) || !core::slice::set(values, 3, 1, negative_zero)) { return 1; }
    let found: f32 = core::slice::get_or(values, 3, 0, 1.0);
    if (found == found) { return 2; }
    if (!core::slice::swap(values, 3, 0, 1)) { return 3; }
    if (!(1.0 / values[0] < 0.0) || values[1] == values[1]) { return 4; }
    if (!core::slice::copy_nonoverlapping_prefix(output, 3, values, 3)) { return 5; }
    if (!(1.0 / output[0] < 0.0) || output[1] == output[1] || output[2] != 7.5) { return 6; }
    if (core::slice::reverse_in_place(output, 3) != 1 || output[0] != 7.5 ||
        output[1] == output[1] || !(1.0 / output[2] < 0.0)) { return 7; }
    if (!core::slice::copy_within(output, 3, 1, 3, 0) || output[0] == output[0] ||
        !(1.0 / output[1] < 0.0)) { return 8; }
    if (core::slice::fill(output, 3, nan) != 3 || output[0] == output[0] ||
        output[1] == output[1] || output[2] == output[2]) { return 9; }
    return 0;
}
fn main() -> i32 {
    let values: [f32; 3] = [0.0, 0.0, 7.5];
    let output: [f32; 3] = [0.0, 0.0, 0.0];
    return exercise(values, output);
}
"#;
    let bytes = compile_source("generic slice float representation", source)
        .expect("compile float mutation and copying");
    assert_native_exit("generic slice float representation", &bytes, 0);
}

#[test]
fn generic_slice_access_preserves_native_physical_bounds() {
    for statement in [
        "return core::slice::first(empty);",
        "return core::slice::get_or(values, 4, 3, 42);",
        "return core::slice::fill(values, 4, 42);",
        "core::slice::swap(values, 4, 0, 3); return 0;",
    ] {
        let source = format!(
            "module app::main; import core::slice; import core::mem; fn main() -> i32 {{\n\
             let values: [i32; 3] = [-7, 0, 99];\n\
             let empty: [i32] = core::mem::i32_slice_from_raw_parts(core::mem::i32_array_data_ptr(values), 0);\n\
             {statement} }}"
        );
        let bytes = compile_source("generic slice physical bounds", &source)
            .expect("compile bounds checks through specialized slice bodies");
        assert_native_exit(statement, &bytes, 101);
    }
}

#[test]
fn generic_slice_summary_program_executes_with_option_ranges_and_arithmetic() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/optional_reading_summary.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("generic slice summary", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile the reading-summary program using generic slice access");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("generic slice summary", "slice_generic", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"4\n20\n", "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

fn compile_source(label: &str, source: &str) -> Result<Vec<u8>, CompileError> {
    let entry = common::TempArtifact::new("slice_generic", label, Some("lani"));
    entry.write_str(source);
    let path = entry.path().to_path_buf();
    let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
    })
}

fn assert_native_exit(label: &str, bytes: &[u8], expected: i32) {
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(label, "slice_generic", bytes);
        assert_eq!(output.status.code(), Some(expected), "{label}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{label}: {output:?}"
        );
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (label, bytes, expected);
}
