use std::{fs, process::Command};

mod common;

#[test]
fn wasm_codegen_current_slice_is_not_primitive_helper_execution() {
    let gpu_wasm = include_str!("../src/codegen/gpu_wasm.rs");
    let simple_lets = include_str!("../shaders/codegen/wasm_simple_lets.slang");
    let module = include_str!("../shaders/codegen/wasm_module.slang");
    let i32_helpers = include_str!("../stdlib/core/i32.lani");
    let bool_helpers = include_str!("../stdlib/core/bool.lani");
    let assert_helpers = include_str!("../stdlib/test/assert.lani");

    assert!(i32_helpers.contains("module core::i32;"));
    assert!(i32_helpers.contains("pub fn abs(value: i32) -> i32"));
    assert!(i32_helpers.contains("return abs(value);"));
    assert!(i32_helpers.contains("while (power < value)"));
    assert!(bool_helpers.contains("module core::bool;"));
    assert!(assert_helpers.contains("assert(value);"));

    assert!(gpu_wasm.contains("codegen.wasm.simple_lets"));
    assert!(gpu_wasm.contains("codegen.wasm.module"));
    assert!(gpu_wasm.contains("pack_output.spv"));
    assert!(
        !gpu_wasm.contains("wasm_functions.spv"),
        "default WASM codegen should stay unavailable for function-helper modules until HIR-driven lowering exists"
    );
    assert!(simple_lets.contains("ERR_UNSUPPORTED_SOURCE_SHAPE"));
    assert!(
        !simple_lets.contains("hir_kind") && !module.contains("hir_kind"),
        "current default WASM emitters are token/source driven, not HIR-driven helper lowering"
    );
}

#[test]
fn docs_name_smallest_gpu_only_primitive_helper_slice() {
    let backend_paper = normalize_doc_whitespace(include_str!("../docs/ParallelCodeGeneration.md"));
    let requirements_doc =
        normalize_doc_whitespace(include_str!("../stdlib/LANGUAGE_REQUIREMENTS.md"));

    for needle in [
        "semantic analysis stage",
        "abstract syntax tree",
        "node type and resulting data type",
    ] {
        assert!(
            backend_paper.contains(needle),
            "backend paper text should describe AST/type-driven code generation: {needle}"
        );
    }

    for needle in [
        "Parser and type-check coverage for `stdlib/core/*.lani` seeds is not execution",
        "default WASM backend does not wire the stalled function-module shader path",
        "HIR-driven WASM lowering for no-loop scalar helpers",
        "Partial for frontend; blocked for execution",
    ] {
        assert!(
            requirements_doc.contains(needle),
            "stdlib requirements should separate frontend coverage from backend execution: {needle}"
        );
    }
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_emits_wasm_for_top_level_lets() {
    let src = "let x = 1;\nlet y = 2;\n";
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_cli_emits_wasm_file() {
    let src_path = common::TempArtifact::new("laniusc_gpu_wasm", "cli_source", Some("lani"));
    let out_path = common::TempArtifact::new("laniusc_gpu_wasm", "cli_output", Some("wasm"));
    src_path.write_str("let x = 1;\n");

    let bin = option_env!("CARGO_BIN_EXE_laniusc").unwrap_or("target/debug/laniusc");
    let mut command = Command::new(bin);
    command
        .env("LANIUS_READBACK", "0")
        .env("PERF_ONE_READBACK", "0")
        .arg("--emit")
        .arg("wasm")
        .arg(src_path.path())
        .arg("-o")
        .arg(out_path.path());
    let output = common::command_output_with_timeout("laniusc --emit wasm", &mut command);

    common::assert_command_success("laniusc --emit wasm", &output);
    let wasm = fs::read(out_path.path()).expect("read emitted WASM");
    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_rejects_function_bodies_when_gpu_emitter_cannot_emit_them() {
    let src = "fn main() {\n    return 0;\n}\n";
    let err = common::compile_source_to_wasm_with_timeout(src)
        .expect_err("function-body WASM lowering should fail until the GPU path supports it");
    let message = err.to_string();
    assert!(
        message.contains("GPU WASM emitter rejected unsupported source shape"),
        "unexpected function-body rejection: {message}"
    );
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_rejects_for_loops_with_gpu_written_status() {
    let src = r#"
fn main(values: [i32]) {
    for value in values {
        let copied: i32 = value;
        continue;
    }
    return 0;
}
"#;
    let err = common::compile_source_to_wasm_with_timeout(src)
        .expect_err("for-loop WASM lowering should fail until the GPU path supports it");
    let message = err.to_string();
    assert!(
        message.contains("unsupported for loop"),
        "unexpected for-loop rejection: {message}"
    );
}

fn assert_lanius_wasm(bytes: &[u8]) {
    assert!(
        bytes.len() >= 37,
        "WASM output too small: {} bytes",
        bytes.len()
    );
    assert_eq!(
        &bytes[0..8],
        &[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
    );
    assert!(contains_bytes(bytes, b"\x03env\x09print_i64"));
    assert!(contains_bytes(bytes, b"\x04main\x00"));
}

fn run_wasm_main_if_node_available(wasm: &[u8], expected_stdout: &str) {
    if !common::node_available() {
        return;
    }
    let stdout = common::run_wasm_main_with_node("codegen WASM check", "codegen_wasm", wasm);
    assert_eq!(
        stdout, expected_stdout,
        "codegen WASM stdout mismatch\nexpected:\n{expected_stdout:?}\nactual:\n{stdout:?}"
    );
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    haystack
        .windows(needle.len())
        .any(|candidate| candidate == needle)
}

fn normalize_doc_whitespace(source: &str) -> String {
    source.split_whitespace().collect::<Vec<_>>().join(" ")
}
