use std::{fs, process::Command};

mod common;

#[test]
fn gpu_codegen_executes_record_driven_arithmetic_sample() {
    let src = include_str!("../sample_programs/arithmetic_precedence.lani");
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "7\n9\n");
}

#[test]
fn gpu_codegen_executes_record_driven_compound_assignments_sample() {
    let src = include_str!("../sample_programs/compound_assignments.lani");
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "3\n");
}

#[test]
fn gpu_codegen_executes_record_driven_bool_branch_sample() {
    let src = include_str!("../sample_programs/bool_branch.lani");
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "1\n");
}

#[test]
fn gpu_codegen_executes_record_driven_comparison_matrix_sample() {
    let src = include_str!("../sample_programs/comparison_matrix.lani");
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "1\n2\n3\n4\n");
}

#[test]
fn gpu_codegen_executes_record_driven_comparison_else_matrix_sample() {
    let src = include_str!("../sample_programs/comparison_else_matrix.lani");
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "10\n21\n31\n40\n");
}

#[test]
fn gpu_codegen_executes_record_driven_bitwise_ops_sample() {
    let src = include_str!("../sample_programs/bitwise_ops.lani");
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "5\n");
}

#[test]
fn gpu_codegen_executes_record_driven_function_calls_sample() {
    let src = include_str!("../sample_programs/function_calls.lani");
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "42\n");
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
fn gpu_codegen_emits_wasm_for_hir_main_return_literal() {
    let src = "fn main() {\n    return 1 - 1;\n}\n";
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_emits_wasm_for_hir_main_local_lets_and_precedence() {
    let src =
        "fn main() {\n    let x: i32 = 1;\n    let y: i32 = x + 2 * 3;\n    return y - 7;\n}\n";
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_emits_wasm_for_hir_main_terminal_if_else_returns() {
    let src =
        "fn main() {\n    let x: i32 = 4;\n    if (x > 3) { return 0; } else { return 1; }\n}\n";
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_emits_wasm_for_hir_main_boolean_operators() {
    let src = "fn main() {\n    let x: i32 = 2;\n    if (((x > 0) && !(x < 2)) || false) { return 0; } else { return 1; }\n}\n";
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_emits_wasm_for_hir_main_nested_terminal_if_else_returns() {
    let src = "fn main() {\n    let value: i32 = 4;\n    if (value < 0) { return 1; } else { if (value > 3) { return 0; } else { return 1; } }\n}\n";
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_emits_wasm_for_hir_main_top_level_scalar_const() {
    let src = "const LIMIT: i32 = 3;\nfn main() {\n    return LIMIT - 3;\n}\n";
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_emits_wasm_for_hir_direct_scalar_helper_call() {
    let src = "fn add_one(value: i32) -> i32 {\n    return value + 1;\n}\nfn main() {\n    return add_one(-1);\n}\n";
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "GPU WASM codegen integration test; run explicitly with --ignored"]
fn gpu_codegen_emits_wasm_from_explicit_source_pack() {
    let sources = [
        "const UNUSED: i32 = 0;\n",
        "fn add_one(value: i32) -> i32 {\n    return value + 1;\n}\nfn main() {\n    return add_one(-1);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_source_pack_qualified_scalar_helper_call() {
    let sources = [
        "module core::math;\npub fn add_one(value: i32) -> i32 {\n    return value + 1;\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    return core::math::add_one(-1);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_source_pack_selected_helper_with_unused_helpers() {
    let sources = [
        "module core::math;\npub fn unused_before(value: i32) -> i32 {\n    return value + 9;\n}\npub fn add_one(value: i32) -> i32 {\n    return value + 1;\n}\npub fn unused_after(value: i32) -> i32 {\n    return value - 7;\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    return core::math::add_one(-1);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_source_pack_selected_branchy_helper() {
    let sources = [
        "module core::math;\npub fn abs(value: i32) -> i32 {\n    if (value < 0) {\n        return -value;\n    } else {\n        return value;\n    }\n}\n",
        "module app::main;\nimport core::math;\nfn main() {\n    return core::math::abs(-7) - 7;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_selected_helper_with_unused_unemittable_helpers() {
    let sources = [
        r#"
module core::math;

pub fn choose(condition: bool, when_true: i32, when_false: i32) -> i32 {
    return when_true;
}

pub fn branchy(value: i32) -> i32 {
    if (value < 0) {
        return -value;
    } else {
        return value;
    }
}

pub fn add_one(value: i32) -> i32 {
    return value + 1;
}
"#,
        "module app::main;\nimport core::math;\nfn main() {\n    return core::math::add_one(-1);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_core_bool_not_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/bool.lani"),
        "module app::main;\nimport core::bool;\nfn main() {\n    let value: bool = core::bool::not(true);\n    return 0;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_core_bool_and_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/bool.lani"),
        "module app::main;\nimport core::bool;\nfn main() -> bool {\n    return core::bool::and(true, false);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 0);
}

#[test]
fn gpu_codegen_executes_core_bool_or_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/bool.lani"),
        "module app::main;\nimport core::bool;\nfn main() -> bool {\n    return core::bool::or(true, false);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_bool_xor_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/bool.lani"),
        "module app::main;\nimport core::bool;\nfn main() -> bool {\n    return core::bool::xor(true, false);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_bool_eq_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/bool.lani"),
        "module app::main;\nimport core::bool;\nfn main() -> bool {\n    return core::bool::eq(true, true);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_bool_from_i32_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/bool.lani"),
        "module app::main;\nimport core::bool;\nfn main() -> bool {\n    return core::bool::from_i32(9);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_i32_abs_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::abs(-7) - 7;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_core_i32_min_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::min(9, 4) - 4;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_core_i32_max_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::max(2, 7) - 7;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_core_i32_is_zero_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() -> bool {\n    return core::i32::is_zero(0);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_i32_is_negative_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() -> bool {\n    return core::i32::is_negative(-3);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_i32_is_positive_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() -> bool {\n    return core::i32::is_positive(5);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_i32_wrapping_add_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::wrapping_add(2, 3) - 5;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_core_i32_wrapping_sub_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::wrapping_sub(9, 1) - 8;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_core_i32_wrapping_mul_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::wrapping_mul(4, 5) - 20;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_core_u32_max_const_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> bool {\n    return core::u32::MAX == 4294967295;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u32_min_const_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> bool {\n    return core::u32::MIN == 0;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u32_min_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> bool {\n    return core::u32::min(9, 4) == 4;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u32_max_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> bool {\n    return core::u32::max(9, 4) == 9;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u32_wrapping_sub_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() {\n    return core::u32::wrapping_sub(0, 1) + 1;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_core_u32_is_zero_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> bool {\n    return core::u32::is_zero(0);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_ascii_digit_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_ascii_digit(53);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_max_const_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::MAX == 255;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_min_const_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::MIN == 0;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_min_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::min(9, 4) == 4;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_max_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::max(9, 4) == 9;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_wrapping_mul_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::wrapping_mul(20, 13) == 4;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_is_zero_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_zero(0);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_ascii_lowercase_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_ascii_lowercase(113);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_ascii_uppercase_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_ascii_uppercase(81);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_ascii_alphabetic_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_ascii_alphabetic(113);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_ascii_alphanumeric_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_ascii_alphanumeric(55);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_ascii_hexdigit_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_ascii_hexdigit(70);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_u8_ascii_hexdigit_false_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_ascii_hexdigit(71);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 0);
}

#[test]
fn gpu_codegen_executes_core_u8_ascii_whitespace_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_ascii_whitespace(10);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_ordering_unit_enum_match_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/ordering.lani"),
        r#"
module app::main;

import core::ordering;

fn main() {
    let order: core::ordering::Ordering = core::ordering::compare_i32(4, 2);
    return match (order) {
        core::ordering::Less -> 1,
        core::ordering::Equal -> 2,
        core::ordering::Greater -> 0,
    };
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
fn gpu_codegen_executes_core_option_is_some_tag_match_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn main() -> bool {
    let value: core::option::Option<i32> = core::option::Some(7);
    return core::option::is_some(value);
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
fn gpu_codegen_executes_core_option_is_some_unit_tag_match_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/option.lani"),
        r#"
module app::main;

import core::option;

fn main() -> bool {
    let value: core::option::Option<i32> = core::option::None;
    return core::option::is_some(value);
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 0);
}

#[test]
fn gpu_codegen_executes_core_result_is_ok_err_tag_match_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/result.lani"),
        r#"
module app::main;

import core::result;

fn main() -> bool {
    let value: core::result::Result<i32, bool> = core::result::Err(false);
    return core::result::is_ok(value);
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 0);
}

#[test]
fn gpu_codegen_executes_source_pack_qualified_scalar_const() {
    let sources = [
        "module core::limits;\npub const ZERO: i32 = 0;\n",
        "module app::main;\nimport core::limits;\nfn main() {\n    return core::limits::ZERO;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
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

fn run_wasm_main_return_if_node_available(wasm: &[u8], expected_status: i32) {
    if !common::node_available() {
        return;
    }
    let status =
        common::run_wasm_main_return_with_node("codegen WASM return check", "codegen_wasm", wasm);
    assert_eq!(status, expected_status, "WASM main return mismatch");
}

fn contains_bytes(haystack: &[u8], needle: &[u8]) -> bool {
    haystack
        .windows(needle.len())
        .any(|candidate| candidate == needle)
}
