mod common;

use laniusc_compiler::compiler::{
    compile_entry_to_x86_64_with_stdlib,
    compile_source_to_x86_64_with_gpu_codegen,
};

#[test]
fn borrowed_slice_iteration_executes_with_stdlib_and_option_payloads() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (fixture, relative, expected) in [
        (
            "minimal",
            "tests/fixtures/stdlib_foundation/repro_borrowed_slice_iteration.lani",
            "",
        ),
        (
            "integration",
            "tests/fixtures/stdlib_foundation/slice_iteration.lani",
            "",
        ),
        (
            "runtime lengths across calls",
            "tests/fixtures/stdlib_foundation/slice_runtime_call_lengths.lani",
            "",
        ),
        (
            "summary",
            "sample_programs/optional_slice_summary.lani",
            "4\n20\n",
        ),
    ] {
        let entry = root.join(relative);
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(fixture, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
        })
        .expect("compile borrowed slice iteration through the real stdlib");
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(fixture, fixture, &bytes);
            assert_eq!(output.status.code(), Some(0), "{fixture}: {output:?}");
            assert_eq!(output.stdout, expected.as_bytes(), "{fixture}: {output:?}");
            assert!(output.stderr.is_empty(), "{fixture}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn borrowed_scalar_slice_iteration_preserves_element_types() {
    // Parameter views exercise fixed-array coercion and each scalar's load
    // behavior independently of the raw-parts intrinsic and stdlib linker.
    for (name, element, values, condition) in [
        ("signed", "i32", "[-7, 0, 11]", "value < 0"),
        (
            "unsigned",
            "u32",
            "[0, 1, 4294967295]",
            "value > 2147483647",
        ),
        ("byte", "u8", "[0, 1, 255]", "value == 255"),
        ("boolean", "bool", "[false, true, false]", "value"),
        ("float", "f32", "[-2.5, 0.0, 3.5]", "value < 0.0"),
    ] {
        let elements: Vec<_> = values.trim_matches(['[', ']']).split(',').collect();
        let source = format!(
            "fn count(values: [{element}]) -> i32 {{\n\
             let total: i32 = 0; let selected: i32 = 0;\n\
             for value in values {{ total = total + 1; if ({condition}) {{ selected = selected + 1; }} }}\n\
             if (total != 3) {{ return 1; }} if (selected != 1) {{ return 2; }} return 0; }}\n\
             fn main() -> i32 {{ let first: {element} = {}; let second: {element} = {}; \
             let third: {element} = {}; let backing: [{element}; 3] = [first, second, third]; \
             return count(backing); }}",
            elements[0], elements[1], elements[2],
        );
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect("compile concrete scalar slice loop");
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, "scalar_slice_iteration", &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn unsupported_slice_iterable_expressions_fail_explicitly() {
    let source = r#"
struct View { values: [i32] }
fn sum(values: [i32]) -> i32 {
    let view: View = View { values: values };
    let total: i32 = 0;
    for value in view.values { total = total + value; }
    return total;
}
fn main() -> i32 { let values: [i32; 3] = [4, 7, -9]; return sum(values); }
"#;
    let error = common::run_gpu_codegen_with_timeout("projected slice iterable", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect_err("unsupported projected iterables must not silently skip execution");
    match error {
        laniusc_compiler::compiler::CompileError::Diagnostic(diagnostic) => {
            // The current for grammar accepts named views and ranges. This
            // expression must fail before producing an executable.
            assert_eq!(diagnostic.code, "LNC0016", "{}", diagnostic.render());
            assert!(
                diagnostic
                    .primary_label
                    .unwrap()
                    .source_line
                    .unwrap()
                    .contains("for value in view.values"),
                "diagnostic must identify the unsupported loop"
            );
        }
        other => panic!("expected a source diagnostic, got {other:?}"),
    }
}

#[test]
fn array_and_range_iteration_preserve_existing_behavior() {
    let source = r#"
fn sum(values: [i32; 3]) -> i32 {
    let total: i32 = 0;
    for value in values { total = total + value; }
    return total;
}
fn main() -> i32 {
    let values: [i32; 3] = [4, 7, -9];
    if (sum(values) != 2) { return 1; }
    let total: i32 = 0;
    let end: i32 = 4;
    for value in 0..end { total = total + value; }
    if (total != 6) { return 2; }
    let inclusive: i32 = 0;
    for value in 2 ..= 5 { inclusive = inclusive + value; }
    if (inclusive != 14) { return 3; }
    return 0;
}

"#;
    let bytes = common::run_gpu_codegen_with_timeout("array and range iteration", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("compile existing array and range recipes");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "array and range iteration",
            "iteration_regression",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn struct_array_iteration_preserves_record_payloads() {
    let source = include_str!("fixtures/stdlib_foundation/repro_struct_array_iteration.lani");
    let bytes = common::run_gpu_codegen_with_timeout("struct-array iteration", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("compile struct-array iteration");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "struct-array iteration",
            "struct_array_iteration",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
