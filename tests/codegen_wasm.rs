mod common;

#[test]
fn wasm_executes_representative_sample_programs() {
    let cases = [
        (
            "arithmetic_precedence",
            include_str!("../sample_programs/arithmetic_precedence.lani"),
            "7\n9\n",
        ),
        (
            "bool_branch",
            include_str!("../sample_programs/bool_branch.lani"),
            "1\n",
        ),
        (
            "function_calls",
            include_str!("../sample_programs/function_calls.lani"),
            "42\n",
        ),
    ];

    for (name, src, expected_stdout) in cases {
        let wasm = common::compile_source_to_wasm_with_timeout(src)
            .unwrap_or_else(|err| panic!("{name} should compile to WASM: {err}"));

        assert_wasm_header(&wasm);
        run_wasm_main_if_node_available(&wasm, expected_stdout);
    }
}

#[test]
fn wasm_executes_source_pack_function_call() {
    let sources = [
        "module core::math;\npub fn add_one(value: i32) -> i32 {\n    return value + 1;\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    return core::math::add_one(-1);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_wasm_header(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn wasm_executes_source_pack_branch() {
    let sources = [
        "module core::math;\npub fn abs(value: i32) -> i32 {\n    if (value < 0) {\n        return -value;\n    } else {\n        return value;\n    }\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    return core::math::abs(-7) - 7;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_wasm_header(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn wasm_executes_stdlib_option_and_result_helpers() {
    let cases = [
        (
            "option_some",
            include_str!("../stdlib/core/option.lani"),
            r#"
module app::main;

import core::option;

fn main() -> bool {
    let value: core::option::Option<i32> = core::option::Some(7);
    return core::option::is_some(value);
}
"#,
            1,
        ),
        (
            "result_err",
            include_str!("../stdlib/core/result.lani"),
            r#"
module app::main;

import core::result;

fn main() -> bool {
    let value: core::result::Result<i32, bool> = core::result::Err(false);
    return core::result::is_ok(value);
}
"#,
            0,
        ),
    ];

    for (name, stdlib, app, expected_status) in cases {
        let sources = [stdlib, app];
        let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources)
            .unwrap_or_else(|err| panic!("{name} should compile to WASM: {err}"));

        assert_wasm_header(&wasm);
        run_wasm_main_return_if_node_available(&wasm, expected_status);
    }
}

#[test]
fn wasm_executes_source_pack_qualified_const() {
    let sources = [
        "module core::limits;\npub const ZERO: i32 = 0;\n",
        "module app::main;\nimport core::limits;\nfn main() {\n    return core::limits::ZERO;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_wasm_header(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

fn assert_wasm_header(bytes: &[u8]) {
    assert!(
        bytes.len() >= 8,
        "WASM output too small: {} bytes",
        bytes.len()
    );
    assert_eq!(
        &bytes[0..8],
        &[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
    );
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

fn run_wasm_main_return_if_node_available(wasm: &[u8], expected_status: i32) {
    if !common::node_available() {
        return;
    }
    let status =
        common::run_wasm_main_return_with_node("codegen WASM return check", "codegen_wasm", wasm);
    assert_eq!(status, expected_status, "WASM main return mismatch");
}
