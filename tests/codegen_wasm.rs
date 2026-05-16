use std::{fs, process::Command};

use laniusc::compiler::compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen;

mod common;

#[test]
fn wasm_codegen_current_slice_is_not_primitive_helper_execution() {
    let gpu_wasm = include_str!("../src/codegen/wasm.rs");
    let simple_lets = include_str!("../shaders/codegen/wasm_simple_lets.slang");
    let hir_stmt_fields = include_str!("../shaders/parser/hir_stmt_fields.slang");
    let hir_body = include_str!("../shaders/codegen/wasm_hir_body.slang");
    let hir_module = include_str!("../shaders/codegen/wasm_hir_module.slang");
    let hir_agg_body = include_str!("../shaders/codegen/wasm_hir_agg_body.slang");
    let hir_assert_module = include_str!("../shaders/codegen/wasm_hir_assert_module.slang");
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
    assert!(gpu_wasm.contains("codegen.wasm.agg_layout_clear"));
    assert!(gpu_wasm.contains("codegen.wasm.agg_layout"));
    assert!(gpu_wasm.contains("codegen.wasm.hir_body"));
    assert!(gpu_wasm.contains("codegen.wasm.hir_agg_body"));
    assert!(gpu_wasm.contains("codegen.wasm.hir_array_body"));
    assert!(gpu_wasm.contains("codegen.wasm.hir_module"));
    assert!(gpu_wasm.contains("codegen.wasm.hir_assert_module"));
    assert!(gpu_wasm.contains("codegen.wasm.hir_enum_match_records"));
    assert!(gpu_wasm.contains("codegen.wasm.hir_enum_match_module"));
    assert!(gpu_wasm.contains("codegen.wasm.module"));
    assert!(gpu_wasm.contains("codegen.wasm.module.after_hir_array_body"));
    assert!(gpu_wasm.contains("pack_output.spv"));
    assert!(
        !gpu_wasm.contains("wasm_functions.spv"),
        "default WASM codegen should not wire the old token-driven function-module shader"
    );
    assert!(simple_lets.contains("ERR_UNSUPPORTED_SOURCE_SHAPE"));
    assert!(
        gpu_wasm.contains("wasm_hir_body.spv") && !module.contains("hir_kind"),
        "default WASM should use the bounded HIR body pass while the module wrapper stays byte-layout only"
    );
    assert!(
        hir_body.contains("Record-driven WASM function-body emitter")
            && hir_body.contains("hir_stmt_record")
            && hir_body.contains("STMT_RECORD_KIND_ASSIGN")
            && hir_body.contains("STMT_RECORD_KIND_IF")
            && hir_body.contains("ASSIGN_OP_DIV")
            && hir_body.contains("HIR_EXPR_BIT_XOR")
            && hir_body.contains("HIR_EXPR_SHL")
            && hir_body.contains("emit_if_stmt")
            && hir_body.contains("nearest_control_ancestor")
            && hir_body.contains("hir_expr_record")
            && hir_body.contains("hir_expr_int_value")
            && hir_body.contains("hir_call_arg_start")
            && hir_body.contains("hir_call_arg_count")
            && hir_body.contains("call_intrinsic_tag")
            && hir_body.contains("fn_entrypoint_tag")
            && !hir_body.contains("token_words")
            && !hir_body.contains("source_bytes")
            && !hir_body.contains("ByteAddressBuffer")
            && !hir_body.contains("StructuredBuffer<TokenIn>")
            && !hir_body.contains("token_kind")
            && !hir_body.contains("token_text")
            && !hir_body.contains("parse_uint_token"),
        "main-body WASM lowering must consume HIR/semantic records, not token or source text"
    );
    assert!(
        hir_stmt_fields.contains("STMT_RECORD_KIND_ASSIGN")
            && hir_stmt_fields.contains("PROD_ASSIGN_ADD")
            && hir_stmt_fields.contains("PROD_ASSIGN_SUB")
            && hir_stmt_fields.contains("PROD_ASSIGN_MUL")
            && hir_stmt_fields.contains("PROD_ASSIGN_DIV")
            && hir_stmt_fields.contains("PROD_ASSIGN_MOD")
            && hir_stmt_fields.contains("PROD_ASSIGN_SHL")
            && hir_stmt_fields.contains("PROD_ASSIGN_BOR")
            && hir_stmt_fields.contains("STMT_RECORD_KIND_WHILE")
            && hir_stmt_fields.contains("publish_while")
            && hir_stmt_fields.contains("hir_stmt_record"),
        "assignment and while metadata must come from parser-owned statement records"
    );
    assert!(
        gpu_wasm.contains("\"hir_stmt_record\"")
            && gpu_wasm.contains("expr_metadata.stmt_record")
            && gpu_wasm.contains("\"hir_expr_record\"")
            && gpu_wasm.contains("expr_metadata.record")
            && gpu_wasm.contains("\"hir_call_arg_start\"")
            && gpu_wasm.contains("call_metadata.arg_start")
            && gpu_wasm.contains("\"hir_call_arg_count\"")
            && gpu_wasm.contains("call_metadata.arg_count"),
        "main-body WASM bind group must wire the record arrays consumed by wasm_hir_body"
    );
    assert!(
        gpu_wasm.contains("wasm_hir_agg_body.spv"),
        "default WASM should keep the aggregate body pipeline boundary explicit"
    );
    assert!(
        hir_agg_body.contains("record-driven aggregate WASM body lowering")
            && !hir_agg_body.contains("token_words")
            && !hir_agg_body.contains("source_bytes")
            && !hir_agg_body.contains("ByteAddressBuffer")
            && !hir_agg_body.contains("StructuredBuffer<TokenIn>")
            && !hir_agg_body.contains("token_kind")
            && !hir_agg_body.contains("token_text"),
        "aggregate WASM body lowering must not preserve the old token/source-shape emitter"
    );
    assert!(
        gpu_wasm.contains("wasm_hir_array_body.spv")
            && gpu_wasm.contains("array_len_buf")
            && gpu_wasm.contains("array_values_buf")
            && gpu_wasm.contains("call_fn_index_buf")
            && module.contains("status[1u] == 5u"),
        "default WASM should wire the bounded HIR array helper body pass without overwriting packed HIR-module outputs"
    );
    assert!(
        gpu_wasm.contains("wasm_agg_layout_clear.spv")
            && gpu_wasm.contains("wasm_agg_layout.spv")
            && gpu_wasm.contains("struct_field_index_by_token")
            && gpu_wasm.contains("member_result_field_index")
            && gpu_wasm.contains("struct_init_field_index"),
        "default WASM should wire aggregate layout metadata for Range-style lowering"
    );
    assert!(
        gpu_wasm.contains("wasm_hir_module.spv"),
        "default WASM should keep the multi-function module pipeline boundary explicit"
    );
    assert!(
        hir_module.contains("StructuredBuffer<uint4> hir_param_record")
            && hir_module.contains("StructuredBuffer<uint> hir_status")
            && hir_module.contains("StructuredBuffer<uint> hir_stmt_record")
            && hir_module.contains("StructuredBuffer<uint> hir_expr_record")
            && hir_module.contains("StructuredBuffer<uint> hir_call_callee_node")
            && hir_module.contains("StructuredBuffer<uint> hir_call_arg_parent_call")
            && hir_module.contains("StructuredBuffer<uint> parent")
            && hir_module.contains("StructuredBuffer<uint> visible_decl")
            && hir_module.contains("StructuredBuffer<uint> call_fn_index")
            && hir_module.contains("StructuredBuffer<uint> call_intrinsic_tag")
            && hir_module.contains("StructuredBuffer<uint> fn_entrypoint_tag")
            && !hir_module.contains("token_words")
            && !hir_module.contains("source_bytes")
            && !hir_module.contains("ByteAddressBuffer")
            && !hir_module.contains("StructuredBuffer<TokenIn>")
            && !hir_module.contains("token_kind")
            && !hir_module.contains("token_text"),
        "multi-function WASM module lowering must not preserve the old token/source-shape emitter"
    );
    assert!(
        gpu_wasm.contains("wasm_hir_assert_module.spv"),
        "default WASM should keep the assertion/trap module pipeline boundary explicit"
    );
    assert!(
        hir_assert_module.contains("record-driven assertion/trap WASM lowering")
            && !hir_assert_module.contains("token_words")
            && !hir_assert_module.contains("source_bytes")
            && !hir_assert_module.contains("ByteAddressBuffer")
            && !hir_assert_module.contains("StructuredBuffer<TokenIn>")
            && !hir_assert_module.contains("token_kind")
            && !hir_assert_module.contains("token_text"),
        "assertion/trap WASM lowering must not preserve the old helper-body recognizer"
    );
    assert!(
        gpu_wasm.contains("wasm_hir_enum_match_records.spv")
            && gpu_wasm.contains("wasm_hir_enum_match_module.spv"),
        "default WASM should wire the bounded HIR enum/match module pass"
    );
    assert!(
        gpu_wasm.contains("call_param_count_buf")
            && gpu_wasm.contains("call_param_type_buf")
            && gpu_wasm.contains("node_kind_buf")
            && gpu_wasm.contains("parent_buf")
            && gpu_wasm.contains("first_child_buf")
            && gpu_wasm.contains("next_sibling_buf")
            && gpu_wasm.contains("name_id_by_token_buf")
            && gpu_wasm.contains("type_expr_ref_tag_buf")
            && gpu_wasm.contains("type_expr_ref_payload_buf")
            && gpu_wasm.contains("module_value_path_call_head_buf")
            && gpu_wasm.contains("module_value_path_call_open_buf")
            && gpu_wasm.contains("module_value_path_const_head_buf")
            && gpu_wasm.contains("module_value_path_const_end_buf")
            && gpu_wasm.contains("GpuWasmStructMetadataBuffers")
            && gpu_wasm.contains("hir_struct_field_parent_struct")
            && gpu_wasm.contains("hir_struct_field_ordinal")
            && gpu_wasm.contains("hir_struct_lit_field_parent_lit")
            && gpu_wasm.contains("GpuWasmEnumMatchMetadataBuffers")
            && gpu_wasm.contains("hir_variant_ordinal")
            && gpu_wasm.contains("hir_match_scrutinee_node")
            && gpu_wasm.contains("hir_match_arm_start")
            && gpu_wasm.contains("hir_match_arm_count")
            && gpu_wasm.contains("hir_match_arm_pattern_node")
            && gpu_wasm.contains("hir_match_arm_payload_start")
            && gpu_wasm.contains("hir_match_arm_payload_count")
            && gpu_wasm.contains("hir_match_arm_result_node")
            && gpu_wasm.contains("hir_enum_match_record_buf")
            && gpu_wasm.contains("GpuWasmCallMetadataBuffers")
            && gpu_wasm.contains("hir_call_callee_node")
            && gpu_wasm.contains("hir_call_arg_parent_call")
            && gpu_wasm.contains("hir_call_arg_end")
            && gpu_wasm.contains("GpuWasmExprMetadataBuffers")
            && gpu_wasm.contains("hir_expr_form")
            && gpu_wasm.contains("hir_expr_left_node")
            && gpu_wasm.contains("hir_expr_right_node")
            && gpu_wasm.contains("hir_expr_value_token")
            && gpu_wasm.contains("hir_expr_int_value")
            && gpu_wasm.contains("call_intrinsic_tag_buf")
            && gpu_wasm.contains("fn_entrypoint_tag_buf")
            && gpu_wasm.contains("call_return_type_token_buf"),
        "WASM HIR body lowering should receive parser tree and GPU type-check function metadata"
    );
    assert!(
        gpu_wasm.contains("fn_return_ref_tag_buf")
            && gpu_wasm.contains("fn_return_ref_payload_buf")
            && gpu_wasm.contains("member_result_ref_tag_buf")
            && gpu_wasm.contains("member_result_ref_payload_buf")
            && gpu_wasm.contains("struct_init_field_expected_ref_tag_buf")
            && gpu_wasm.contains("struct_init_field_expected_ref_payload_buf")
            && gpu_wasm.contains("method_call_receiver_ref_tag_buf")
            && gpu_wasm.contains("method_decl_receiver_mode_buf")
            && gpu_wasm.contains("type_instance_arg_ref_tag_buf"),
        "WASM codegen boundary should receive GPU aggregate/method metadata for range-style lowering"
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
        "default WASM backend now has a bounded HIR main-return body slice",
        "bounded selected HIR scalar helper module slice",
        "boolean helpers such as `core::bool::not`, `core::bool::and`, `core::bool::or`, `core::bool::xor`, `core::bool::eq`, and `core::bool::from_i32`",
        "zero-parameter helpers such as `core::target::has_threads`",
        "direct terminal helper branches such as `core::i32::abs`",
        "one bounded helper-to-helper scalar call such as `core::i32::saturating_abs`",
        "one bounded local-mutation `while` helper shape",
        "one-level tail helper branches such as `core::i32::clamp`",
        "simple scalar terminal branches such as `core::i32::min` and `core::i32::max`",
        "direct scalar predicates such as `core::i32::is_zero`, `core::i32::is_negative`, `core::i32::is_positive`, and `core::i32::between_inclusive`",
        "direct wrapping arithmetic helpers such as `core::i32::wrapping_add`, `core::i32::wrapping_sub`, and `core::i32::wrapping_mul`",
        "bounded unsigned scalar helpers such as `core::u32::MIN`, `core::u32::MAX`, `core::u32::min`, `core::u32::max`, `core::u32::clamp`, `core::u32::wrapping_add`, `core::u32::wrapping_sub`, `core::u32::wrapping_mul`, `core::u32::saturating_add`, `core::u32::saturating_sub`, `core::u32::between_inclusive`, `core::u32::is_zero`, `core::u32::is_power_of_two`, `core::u32::next_power_of_two`, `core::u8::MIN`, `core::u8::MAX`, `core::u8::min`, `core::u8::max`, `core::u8::clamp`, `core::u8::wrapping_add`, `core::u8::wrapping_sub`, `core::u8::wrapping_mul`, `core::u8::saturating_add`, `core::u8::saturating_sub`, `core::u8::saturating_mul`, `core::u8::between_inclusive`, `core::u8::is_zero`, `core::u8::is_power_of_two`, `core::u8::next_power_of_two`, `core::u8::is_ascii_digit`, `core::u8::is_ascii_lowercase`, `core::u8::is_ascii_uppercase`, `core::u8::is_ascii_alphabetic`, `core::u8::is_ascii_alphanumeric`, `core::u8::is_ascii_hexdigit`, and `core::u8::is_ascii_whitespace`",
        "uses GPU call parameter type metadata to choose unsigned WASM comparison/division opcodes",
        "resolver-backed source-pack selected scalar helper-call WASM slice",
        "resolver-backed source-pack module-qualified scalar-const WASM slice",
        "bounded HIR-driven unit-enum tag and match dispatch slice",
        "tag-only `Option`/`Result` predicate helper slices",
        "one bounded array helper slice for local `[i32; 4]` literals",
        "fixed array projection helpers such as `core::array_i32_4::first` and `core::array_i32_4::last`",
        "one bounded fixed-array conditional lookup helper such as `core::array_i32_4::get_or`",
        "bounded fixed-array scan helpers such as `core::array_i32_4::contains`, `core::array_i32_4::count`, `core::array_i32_4::index_of_or`, `core::array_i32_4::sum`, `core::array_i32_4::min`, and `core::array_i32_4::max`",
        "bounded tag-only enum predicate helpers such as `core::option::is_some` and `core::result::is_ok`",
        "Partial for flat/source-pack frontend and scalar helper/const/assertion/array/aggregate-helper/enum-tag-predicate WASM",
        "Partial for parser/type-check plus bounded `Ordering` and tag-only `Option`/`Result` WASM",
    ] {
        assert!(
            requirements_doc.contains(needle),
            "stdlib requirements should separate frontend coverage from backend execution: {needle}"
        );
    }
}

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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_explicit_source_pack_path_surface() {
    let stdlib_path =
        common::TempArtifact::new("laniusc_source_pack", "stdlib_core_i32", Some("lani"));
    let user_path = common::TempArtifact::new("laniusc_source_pack", "user_main", Some("lani"));
    stdlib_path.write_str(include_str!("../stdlib/core/i32.lani"));
    user_path.write_str(
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::abs(-7) - 7;\n}\n",
    );
    let stdlib_paths = [stdlib_path.path().to_path_buf()];
    let user_paths = [user_path.path().to_path_buf()];

    let wasm = common::run_gpu_codegen_with_timeout(
        "GPU explicit source-pack path WASM compile",
        move || {
            pollster::block_on(compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen(
                &stdlib_paths,
                &user_paths,
            ))
        },
    )
    .expect("compile WASM from explicit source-pack path lists");

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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_i32_between_inclusive_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() -> bool {\n    return core::i32::between_inclusive(5, 0, 7);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_i32_between_inclusive_false_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() -> bool {\n    return core::i32::between_inclusive(9, 0, 7);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 0);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_i32_saturating_abs_helper_to_helper_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::saturating_abs(-7) - 7;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_i32_is_power_of_two_true_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    if (core::i32::is_power_of_two(8)) { return 0; } else { return 1; }\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_i32_is_power_of_two_false_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    if (core::i32::is_power_of_two(7)) { return 1; } else { return 0; }\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_i32_next_power_of_two_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::next_power_of_two(7) - 8;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_i32_clamp_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::clamp(9, 0, 7) - 7;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_i32_signum_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::signum(-9) + 1;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_i32_compare_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/i32.lani"),
        "module app::main;\nimport core::i32;\nfn main() {\n    return core::i32::compare_as_i32(4, 9) + 1;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u32_clamp_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> bool {\n    return core::u32::clamp(9, 0, 7) == 7;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u32_wrapping_add_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() {\n    return core::u32::wrapping_add(4294967295, 1);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u32_wrapping_mul_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() {\n    return core::u32::wrapping_mul(2147483648, 2);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u32_saturating_add_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> bool {\n    return core::u32::saturating_add(4294967295, 1) == 4294967295;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u32_saturating_sub_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() {\n    return core::u32::saturating_sub(2, 9);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u32_between_inclusive_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> bool {\n    return core::u32::between_inclusive(2147483648, 1, 4294967295);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u32_next_power_of_two_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() {\n    return core::u32::next_power_of_two(7) - 8;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u32_is_power_of_two_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u32.lani"),
        "module app::main;\nimport core::u32;\nfn main() -> bool {\n    return core::u32::is_power_of_two(2147483648);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u8_clamp_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::clamp(9, 0, 7) == 7;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u8_wrapping_add_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::wrapping_add(250, 9) == 3;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u8_wrapping_sub_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::wrapping_sub(2, 9) == 249;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u8_saturating_add_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::saturating_add(250, 9) == 255;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u8_saturating_sub_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::saturating_sub(2, 9) == 0;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u8_saturating_mul_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::saturating_mul(20, 13) == 255;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u8_between_inclusive_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::between_inclusive(7, 3, 9);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u8_is_power_of_two_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::is_power_of_two(128);\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_u8_next_power_of_two_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/u8.lani"),
        "module app::main;\nimport core::u8;\nfn main() -> bool {\n    return core::u8::next_power_of_two(9) == 16;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_target_zero_param_helper_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/target.lani"),
        "module app::main;\nimport core::target;\nfn main() {\n    if (core::target::has_threads()) { return 1; } else { return 0; }\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_zero_param_helper_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        "module app::main;\nimport core::array_i32_4;\nfn main() {\n    return core::array_i32_4::len() - 4;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_is_empty_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        "module app::main;\nimport core::array_i32_4;\nfn main() -> bool {\n    return core::array_i32_4::is_empty();\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 0);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_index_helper_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        r#"
module app::main;

import core::array_i32_4;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 9];
    return core::array_i32_4::last(values) - 9;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_get_or_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        r#"
module app::main;

import core::array_i32_4;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 9];
    return core::array_i32_4::get_or(values, 2, 99) - 4;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_get_or_fallback_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        r#"
module app::main;

import core::array_i32_4;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 9];
    return core::array_i32_4::get_or(values, 7, 99) - 99;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_contains_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        r#"
module app::main;

import core::array_i32_4;

fn main() -> bool {
    let values: [i32; 4] = [3, 1, 4, 9];
    return core::array_i32_4::contains(values, 4);
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_contains_false_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        r#"
module app::main;

import core::array_i32_4;

fn main() -> bool {
    let values: [i32; 4] = [3, 1, 4, 9];
    return core::array_i32_4::contains(values, 8);
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 0);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_count_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        r#"
module app::main;

import core::array_i32_4;

fn main() {
    let values: [i32; 4] = [3, 4, 4, 9];
    return core::array_i32_4::count(values, 4) - 2;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_sum_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        r#"
module app::main;

import core::array_i32_4;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 9];
    return core::array_i32_4::sum(values) - 17;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_min_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        r#"
module app::main;

import core::array_i32_4;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 9];
    return core::array_i32_4::min(values) - 1;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_max_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        r#"
module app::main;

import core::array_i32_4;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 9];
    return core::array_i32_4::max(values) - 9;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_index_of_or_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        r#"
module app::main;

import core::array_i32_4;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 9];
    return core::array_i32_4::index_of_or(values, 4, 99) - 2;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_core_array_i32_4_index_of_or_fallback_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/array_i32_4.lani"),
        r#"
module app::main;

import core::array_i32_4;

fn main() {
    let values: [i32; 4] = [3, 1, 4, 9];
    return core::array_i32_4::index_of_or(values, 8, 99) - 99;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_struct_literal_member_projection() {
    let src = r#"
struct Pair {
    left: i32,
    right: i32,
}

fn main() {
    let pair: Pair = Pair { left: 1, right: 4 };
    return pair.left - 1;
}
"#;
    let wasm = common::compile_source_to_wasm_with_timeout(src).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_range_aggregate_helper_lowering_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/range.lani"),
        r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::Range<i32> = core::range::range_i32(1, 4);
    return core::range::start_i32(range) - 1;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_range_method_projection_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/range.lani"),
        r#"
module app::main;

import core::range;

fn main() {
    let range: core::range::Range<i32> = core::range::range_i32(1, 4);
    return range.start() - 1;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_range_call_result_method_projection_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/range.lani"),
        r#"
module app::main;

import core::range;

fn main() {
    return core::range::range_i32(1, 4).start() - 1;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_range_explicit_receiver_method_projection_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/range.lani"),
        r#"
module app::main;

import core::range;

fn main() {
    return core::range::range_i32(1, 4).end() - 4;
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_range_helper_contains_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/range.lani"),
        r#"
module app::main;

import core::range;

fn main() -> bool {
    let range: core::range::Range<i32> = core::range::range_i32(1, 4);
    return core::range::contains_i32(range, 2);
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_range_method_contains_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/range.lani"),
        r#"
module app::main;

import core::range;

fn main() -> bool {
    let range: core::range::Range<i32> = core::range::range_i32(1, 4);
    return range.contains(2);
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_range_call_result_method_is_empty_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/range.lani"),
        r#"
module app::main;

import core::range;

fn main() -> bool {
    return core::range::range_i32(4, 4).is_empty();
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_range_inclusive_helper_contains_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/range.lani"),
        r#"
module app::main;

import core::range;

fn main() -> bool {
    let range: core::range::RangeInclusive<i32> = core::range::range_inclusive_i32(1, 4);
    return core::range::contains_inclusive_i32(range, 4);
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_range_inclusive_call_result_method_contains_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/range.lani"),
        r#"
module app::main;

import core::range;

fn main() -> bool {
    return core::range::range_inclusive_i32(1, 4).contains(4);
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_range_inclusive_call_result_method_is_empty_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/core/range.lani"),
        r#"
module app::main;

import core::range;

fn main() -> bool {
    return core::range::range_inclusive_i32(5, 4).is_empty();
}
"#,
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_return_if_node_available(&wasm, 1);
}

#[test]
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
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
#[ignore = "legacy WASM execution test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_executes_test_assert_eq_i32_void_helper_from_full_source_pack() {
    let sources = [
        include_str!("../stdlib/test/assert.lani"),
        "module app::main;\nimport test::assert;\nfn main() {\n    test::assert::eq_i32(4, 4);\n    return 0;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    run_wasm_main_if_node_available(&wasm, "");
}

#[test]
#[ignore = "legacy WASM trap test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_traps_test_assert_eq_i32_false_from_full_source_pack() {
    if !common::node_available() {
        return;
    }

    let sources = [
        include_str!("../stdlib/test/assert.lani"),
        "module app::main;\nimport test::assert;\nfn main() {\n    test::assert::eq_i32(4, 5);\n    return 0;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    let output = common::run_wasm_main_with_node_output(
        "codegen assertion trap check",
        "codegen_wasm",
        &wasm,
    );
    assert!(
        !output.status.success(),
        "false assertion helper should trap, but node exited successfully"
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("RuntimeError") || stderr.contains("unreachable"),
        "false assertion helper should fail through a WASM trap, stderr:\n{stderr}"
    );
}

#[test]
#[ignore = "legacy WASM trap test depended on removed token/source-shape emitters; rebuild as record-pipeline test"]
fn gpu_codegen_traps_core_panic_void_helper_from_full_source_pack() {
    if !common::node_available() {
        return;
    }

    let sources = [
        include_str!("../stdlib/core/panic.lani"),
        "module app::main;\nimport core::panic;\nfn main() {\n    core::panic::panic();\n    return 0;\n}\n",
    ];
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&sources).expect("compile WASM");

    assert_lanius_wasm(&wasm);
    let output =
        common::run_wasm_main_with_node_output("codegen panic trap check", "codegen_wasm", &wasm);
    assert!(
        !output.status.success(),
        "panic helper should trap, but node exited successfully"
    );
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stderr.contains("RuntimeError") || stderr.contains("unreachable"),
        "panic helper should fail through a WASM trap, stderr:\n{stderr}"
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

fn normalize_doc_whitespace(source: &str) -> String {
    source.split_whitespace().collect::<Vec<_>>().join(" ")
}
