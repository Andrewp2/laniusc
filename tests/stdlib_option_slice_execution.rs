mod common;

use laniusc_compiler::compiler::{CompileError, compile_entry_to_x86_64_with_stdlib};

#[test]
fn imported_option_slice_payloads_execute() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_option_direct_slice_payload.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("imported Option slice", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile Option with a direct borrowed slice payload");
    assert_native_exit("imported Option slice", &bytes, 0);
}

#[test]
fn imported_option_slice_concrete_function_returns_execute() {
    for (name, constructor, condition) in [
        (
            "present function return",
            "core::option::Some(view)",
            "value.is_some()",
        ),
        (
            "absent function return",
            "core::option::None()",
            "value.is_none()",
        ),
    ] {
        let source = format!(
            r#"
module app::main;
import core::option;
fn capture(view: [i32]) -> core::option::Option<[i32]> {{
    let value: core::option::Option<[i32]> = {constructor};
    return value;
}}
fn main() -> i32 {{
    let backing: [i32; 3] = [4, 7, -9];
    let value: core::option::Option<[i32]> = capture(backing);
    if (!{condition}) {{ return 10; }}
    return 0;
}}
"#
        );
        let bytes =
            compile_stdlib_source(name, &source).expect("compile a minimal optional-slice return");
        assert_native_exit(name, &bytes, 0);
    }
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for relative in [
        "tests/fixtures/stdlib_foundation/repro_option_slice_scoped_returns.lani",
        "tests/fixtures/stdlib_foundation/repro_option_slice_loop_return.lani",
    ] {
        let entry = root.join(relative);
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("optional slice return", move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect("compile optional slice returns with branches and iteration");
        assert_native_exit(relative, &bytes, 0);
    }
    let entry = root.join("sample_programs/optional_slice_window.lani");
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("optional borrowed window", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile a concrete function returning an optional borrowed slice");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "optional borrowed window",
            "optional_slice_window",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"4\n20\n", "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_option_slice_payloads_preserve_scalar_types() {
    for (name, element, first, second, third) in [
        ("signed", "i32", "-2147483648", "0", "2147483647"),
        ("unsigned", "u32", "0", "2147483648", "4294967295"),
        ("byte", "u8", "0", "1", "255"),
        ("boolean", "bool", "false", "true", "false"),
        ("float", "f32", "-2.5", "0.0", "3.5"),
    ] {
        let source = format!(
            r#"
module app::main;
import core::option;
fn capture(view: [{element}]) -> core::option::Option<[{element}]> {{
    let present: core::option::Option<[{element}]> = core::option::Some(view);
    return present;
}}
fn missing() -> core::option::Option<[{element}]> {{
    let absent: core::option::Option<[{element}]> = core::option::None();
    return absent;
}}
fn exercise(view: [{element}]) -> i32 {{
    let present: core::option::Option<[{element}]> = capture(view);
    let absent: core::option::Option<[{element}]> = missing();
    if (!present.is_some() || present.is_none() || absent.is_some() || !absent.is_none()) {{ return 1; }}
    if (!core::option::is_some(present) || !core::option::is_none(absent)) {{ return 2; }}
    let recovered: [{element}] = match (present) {{
        core::option::Some(inner) -> inner, core::option::None -> view,
    }};
    let first: {element} = {first}; let second: {element} = {second}; let third: {element} = {third};
    if (recovered[0] != first || recovered[1] != second || recovered[2] != third) {{ return 3; }}
    let count: i32 = 0;
    for value in recovered {{ count = count + 1; }}
    if (count != 3) {{ return 4; }}
    recovered[0] = second;
    if (view[0] != second) {{ return 5; }}
    let fallback: [{element}] = match (absent) {{
        core::option::Some(inner) -> inner, core::option::None -> view,
    }};
    if (fallback[0] != second) {{ return 6; }}
    return 0;
}}
fn main() -> i32 {{
    let first: {element} = {first}; let second: {element} = {second}; let third: {element} = {third};
    let backing: [{element}; 3] = [first, second, third];
    return exercise(backing);
}}
"#
        );
        let bytes = compile_stdlib_source(name, &source)
            .expect("compile direct scalar slice payloads through actual Option definitions");
        assert_native_exit(name, &bytes, 0);
    }
}

#[test]
fn imported_option_slice_payloads_keep_native_bounds() {
    for (name, access) in [
        ("populated bounds", "recovered[3]"),
        ("empty bounds", "empty_recovered[0]"),
    ] {
        let source =
            include_str!("fixtures/stdlib_foundation/repro_option_direct_slice_payload.lani")
                .replace("    return 0;", &format!("    return {access};"));
        let bytes = compile_stdlib_source(name, &source)
            .expect("compile native bounds regression for Option slices");
        assert_native_exit(name, &bytes, 101);
    }
}

#[test]
fn imported_option_slice_payloads_reject_wrong_element_types() {
    for source in [
        r#"
module app::main;
import core::option;
fn exercise(view: [i32]) -> i32 {
    let wrong: core::option::Option<[u8]> = core::option::Some(view);
    return 0;
}
fn main() -> i32 { let values: [i32; 3] = [4, 7, -9]; return exercise(values); }
"#,
        r#"
module app::main;
import core::option;
fn same<T>(left: T, right: T) -> bool { return true; }
fn exercise(left: [i32], right: [u8]) -> i32 {
    if (same(left, right)) { return 0; }
    return 1;
}
fn main() -> i32 {
    let left: [i32; 3] = [4, 7, -9];
    let a: u8 = 4; let b: u8 = 7; let c: u8 = 9;
    let right: [u8; 3] = [a, b, c];
    return exercise(left, right);
}
"#,
        r#"
module app::main;
import core::option;
fn exercise(left: [i32], right: [u8]) -> i32 {
    let present: core::option::Option<[i32]> = core::option::Some(left);
    let wrong: [i32] = match (present) {
        core::option::Some(inner) -> inner, core::option::None -> right,
    };
    return 0;
}
fn main() -> i32 {
    let left: [i32; 3] = [4, 7, -9];
    let a: u8 = 4; let b: u8 = 7; let c: u8 = 9;
    let right: [u8; 3] = [a, b, c];
    return exercise(left, right);
}
"#,
    ] {
        let error = compile_stdlib_source("Option slice wrong element", source)
            .expect_err("slice descriptor width must not erase the element type");
        match error {
            laniusc_compiler::compiler::CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0006", "{}", diagnostic.render());
            }
            other => panic!("expected type mismatch, got {other:?}"),
        }
    }
}

fn compile_stdlib_source(name: &str, source: &str) -> Result<Vec<u8>, CompileError> {
    let entry = common::TempArtifact::new("laniusc_option_slice", "entry", Some("lani"));
    entry.write_str(source);
    let path = entry.path().to_path_buf();
    let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
    })
}

fn assert_native_exit(name: &str, bytes: &[u8], expected: i32) {
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(name, "option_slice", bytes);
        assert_eq!(output.status.code(), Some(expected), "{name}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{name}: {output:?}"
        );
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (name, bytes, expected);
}
