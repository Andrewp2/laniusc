mod common;

use laniusc_compiler::compiler::{
    CompileError,
    compile_entry_to_x86_64_with_stdlib,
    compile_source_to_x86_64_with_gpu_codegen,
};

#[test]
fn unresolved_payload_templates_do_not_poison_imported_executable_functions() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry =
        root.join("tests/fixtures/stdlib_foundation/repro_deferred_generic_payload_import.lani");
    let stdlib = root.join("tests/fixtures/stdlib_foundation/repro_deferred_generic_payload_root");
    let bytes = common::run_gpu_codegen_with_timeout("mixed generic payload library", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile concrete bodies and tag predicates alongside unresolved payload templates");
    assert_native_success("mixed generic payload library", &bytes);
}

#[test]
fn unused_local_payload_templates_preserve_executable_predicates() {
    let definitions = include_str!(
        "fixtures/stdlib_foundation/repro_deferred_generic_payload_root/core/maybe.lani"
    )
    .replace("module core::maybe;", "module app::main;");
    let entry =
        include_str!("fixtures/stdlib_foundation/repro_deferred_generic_payload_import.lani")
            .replace("module app::main;", "")
            .replace("import core::maybe;", "")
            .replace("core::maybe::", "");
    let source = format!("{definitions}\n{entry}");
    let bytes =
        common::run_gpu_codegen_with_timeout("local generic payload templates", move || {
            pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
        })
        .expect("compile executable local functions alongside unresolved templates");
    assert_native_success("local generic payload templates", &bytes);
}

#[test]
fn used_local_payload_templates_execute() {
    let definitions = include_str!(
        "fixtures/stdlib_foundation/repro_deferred_generic_payload_root/core/maybe.lani"
    )
    .replace("module core::maybe;", "module app::main;");
    for body in [
        "if (unwrap_or(present, 99) != -7) { return 1; } return 0;",
        "if (unwrap_or(absent, 99) != 99) { return 1; } return 0;",
        "let selected: Maybe<i32> = prefer(present, absent); let recovered: i32 = match (selected) { Some(inner) -> inner, None -> 99 }; if (recovered != -7) { return 1; } return 0;",
        "prefer(present, absent); return 0;",
        "if (last(choice) != 42) { return 1; } return 0;",
    ] {
        let source = format!(
            "{definitions}\nfn main() -> i32 {{\n\
             let present: Maybe<i32> = Some(-7);\n\
             let absent: Maybe<i32> = None();\n\
             let choice: Choice<i32> = Item(-7, 42);\n\
             {body}\n}}"
        );
        let bytes =
            common::run_gpu_codegen_with_timeout("used local payload template", move || {
                pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
            })
            .expect("local generic payload bodies must execute");
        assert_native_success(body, &bytes);
    }
}

#[test]
fn used_local_slice_element_templates_execute() {
    let source = include_str!("fixtures/stdlib_foundation/repro_generic_slice_local_body.lani");
    let bytes = common::run_gpu_codegen_with_timeout("local slice element template", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(source))
    })
    .expect("local generic slice bodies must execute");
    assert_native_success("local slice element template", &bytes);
}

#[test]
fn imported_scalar_payload_templates_execute_both_branches() {
    for (name, body) in [
        (
            "present",
            "if (core::maybe::unwrap_or(present, 99) != -7) { return 1; } return 0;",
        ),
        (
            "absent",
            "if (core::maybe::unwrap_or(absent, 99) != 99) { return 1; } return 0;",
        ),
        (
            "aggregate",
            "let selected: core::maybe::Maybe<i32> = core::maybe::prefer(present, absent);\n\
             let recovered: i32 = match (selected) { core::maybe::Some(inner) -> inner, core::maybe::None -> 99 };\n\
             if (recovered != -7) { return 1; }\n\
             let fallback: core::maybe::Maybe<i32> = core::maybe::prefer(absent, present);\n\
             let recovered_fallback: i32 = match (fallback) { core::maybe::Some(inner) -> inner, core::maybe::None -> 99 };\n\
             if (recovered_fallback != -7) { return 2; } return 0;",
        ),
        (
            "later payload",
            "if (core::maybe::last(choice) != 42) { return 1; } return 0;",
        ),
    ] {
        let source = format!(
            "module app::main; import core::maybe;\nfn main() -> i32 {{\n\
             let present: core::maybe::Maybe<i32> = core::maybe::Some(-7);\n\
             let absent: core::maybe::Maybe<i32> = core::maybe::None();\n\
             let choice: core::maybe::Choice<i32> = core::maybe::Item(-7, 42);\n\
             {body}\n}}"
        );
        let bytes = compile_imported_source(name, &source)
            .expect("the checked scalar environment must produce a concrete native body");
        assert_native_success(name, &bytes);
    }
}

#[test]
fn imported_receiver_payload_templates_execute_distinct_scalar_instances() {
    let source = r#"
module app::main;
import core::maybe;
fn main() -> i32 {
    let present: core::maybe::Maybe<i32> = core::maybe::Some(-2147483648);
    let absent: core::maybe::Maybe<i32> = core::maybe::None();
    let zero: core::maybe::Maybe<i32> = core::maybe::Some(0);
    if (present.take_or(99) != -2147483648 || absent.take_or(99) != 99 || zero.take_or(99) != 0) { return 1; }
    let false_value: core::maybe::Maybe<bool> = core::maybe::Some(false);
    let missing: core::maybe::Maybe<bool> = core::maybe::None();
    if (false_value.take_or(true) || !missing.take_or(true)) { return 2; }
    if (!core::maybe::is_some(present) || !core::maybe::is_some(false_value)) { return 3; }
    return 0;
}
"#;
    let bytes = compile_imported_source("receiver body specialization", source)
        .expect("instantiate the borrowed receiver's checked scalar environment");
    assert_native_success("receiver body specialization", &bytes);
}

#[test]
fn imported_generic_slice_payloads_execute_reads_writes_and_swaps() {
    for (name, element, zero, other, fallback) in [
        ("signed view", "i32", "0", "-2147483648", "2147483647"),
        ("unsigned view", "u32", "0", "4294967295", "2147483648"),
        ("bool view", "bool", "false", "true", "true"),
        ("float view", "f32", "0.0", "-2.5", "7.5"),
        ("char view", "char", "'\\0'", "'Ω'", "'é'"),
    ] {
        let source = format!(
            r#"
module app::main;
import core::view;
fn exercise(values: [{element}]) -> i32 {{
    let zero: {element} = {zero};
    let other: {element} = {other};
    let fallback: {element} = {fallback};
    if (core::view::get_or(values, 3, 0, fallback) != zero) {{ return 1; }}
    if (core::view::get_or(values, 3, 1, fallback) != other) {{ return 2; }}
    if (core::view::get_or(values, 3, -1, fallback) != fallback) {{ return 3; }}
    if (core::view::get_or(values, 3, 3, fallback) != fallback) {{ return 4; }}
    if (core::view::get_or(values, -1, 0, fallback) != fallback) {{ return 5; }}
    if (!core::view::swap(values, 3, 0, 2)) {{ return 6; }}
    if (values[0] != fallback || values[2] != zero) {{ return 7; }}
    if (core::view::swap(values, 3, -1, 0) || core::view::swap(values, 3, 0, 3)) {{ return 8; }}
    if (core::view::fill(values, -1, other) != 0 || core::view::fill(values, 0, other) != 0) {{ return 9; }}
    if (values[0] != fallback || values[2] != zero) {{ return 10; }}
    if (core::view::fill(values, 2, other) != 2) {{ return 11; }}
    if (values[0] != other || values[1] != other || values[2] != zero) {{ return 12; }}
    return 0;
}}
fn main() -> i32 {{
    let zero: {element} = {zero};
    let other: {element} = {other};
    let fallback: {element} = {fallback};
    let backing: [{element}; 3] = [zero, other, fallback];
    return exercise(backing);
}}
"#
        );
        let entry = common::TempArtifact::new("generic_slice_payload", name, Some("lani"));
        entry.write_str(&source);
        let path = entry.path().to_path_buf();
        let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/stdlib_foundation/repro_generic_slice_payload_root");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&path, &stdlib))
        })
        .expect("specialize generic borrowed-view element loads and stores");
        assert_native_success(name, &bytes);
    }
}
#[test]
fn deferred_template_interfaces_still_check_payload_arguments() {
    for (label, source) in [
        (
            "wrong fallback",
            "module app::main; import core::maybe; fn main() -> i32 {\n\
         let value: core::maybe::Maybe<i32> = core::maybe::Some(-7);\n\
         core::maybe::unwrap_or(value, false); return 0; }",
        ),
        (
            "distinct record types",
            include_str!("fixtures/stdlib_foundation/repro_generic_record_claim_mismatch.lani"),
        ),
        (
            "wrong result annotation",
            "module app::main; import core::maybe; fn main() -> i32 {\n\
             let value: core::maybe::Maybe<i32> = core::maybe::Some(-7);\n\
             let wrong: core::maybe::Maybe<bool> = core::maybe::prefer(value, value); return 0; }",
        ),
    ] {
        let error = compile_imported_source(label, source)
            .expect_err("deferring native emission must preserve the checked generic signature");
        assert!(
            matches!(&error, CompileError::Diagnostic(d) if d.code == "LNC0006"),
            "{label}: {error:?}"
        );
    }
}

#[test]
fn qualified_generic_scalar_returns_execute_after_substitution() {
    let bytes = compile_imported_source(
        "qualified scalar returns",
        r#"
module app::main;
import core::maybe;
fn signed(value: i32) -> i32 { return core::maybe::keep(value); }
fn unsigned(value: u32) -> u32 { return core::maybe::keep(value); }
fn boolean(value: bool) -> bool { return core::maybe::keep(value); }
fn main() -> i32 {
    let minimum: i32 = -2147483648; let maximum: i32 = 2147483647;
    if (signed(minimum) != minimum || signed(maximum) != maximum) { return 1; }
    let zero: u32 = 0; let high: u32 = 2147483648; let all: u32 = 4294967295;
    if (unsigned(zero) != zero || unsigned(high) != high || unsigned(all) != all) { return 2; }
    if (boolean(false) || !boolean(true)) { return 3; }
    return 0;
}
"#,
    )
    .expect("qualified generic scalar return aliases must receive the inferred type");
    assert_native_success("qualified scalar returns", &bytes);
}

fn compile_imported_source(label: &str, source: &str) -> Result<Vec<u8>, CompileError> {
    let entry = common::TempArtifact::new("generic_payload_templates", label, Some("lani"));
    entry.write_str(source);
    let entry_path = entry.path().to_path_buf();
    let stdlib = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/repro_deferred_generic_payload_root");
    common::run_gpu_codegen_with_timeout(label, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry_path, &stdlib))
    })
}

fn assert_native_success(label: &str, bytes: &[u8]) {
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(label, "generic_payload_templates", bytes);
        assert_eq!(output.status.code(), Some(0), "{label}: {output:?}");
        assert!(output.stdout.is_empty(), "{label}: {output:?}");
        assert!(output.stderr.is_empty(), "{label}: {output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = (label, bytes);
}
