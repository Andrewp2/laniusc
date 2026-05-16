use std::fs;

use super::support::{
    assert_contains_all,
    assert_contains_none,
    repo_file,
    repo_path,
    slang_files,
};

#[test]
fn x86_backend_uses_gpu_record_pipeline_without_wasm_translation() {
    let compiler = repo_file("src/compiler.rs");
    let codegen_mod = repo_file("src/codegen/mod.rs");
    let x86_backend = [
        repo_file("src/codegen/x86.rs"),
        repo_file("src/codegen/x86/record.rs"),
        repo_file("src/codegen/x86/record_init.rs"),
        repo_file("src/codegen/x86/record_retained_expr.rs"),
        repo_file("src/codegen/x86/support.rs"),
        repo_file("src/codegen/x86/finish.rs"),
    ]
    .join("\n");

    assert_contains_all(
        &compiler,
        "src/compiler.rs",
        &[
            "record_x86_elf_from_gpu_hir",
            "with_recorded_resident_source_pack_tokens",
        ],
    );
    assert_contains_all(&codegen_mod, "src/codegen/mod.rs", &["pub mod x86;"]);
    assert_contains_all(
        &x86_backend,
        "src/codegen/x86",
        &[
            "x86_node_tree_info.spv",
            "x86_node_inst_counts.spv",
            "x86_node_inst_order.spv",
            "x86_node_inst_scan_local.spv",
            "x86_node_inst_scan_blocks.spv",
            "x86_node_inst_prefix_scan.spv",
            "x86_node_inst_locations.spv",
            "x86_node_inst_gen.spv",
            "x86_virtual_use_edges.spv",
            "x86_virtual_liveness.spv",
            "x86_virtual_regalloc.spv",
            "x86_lower_values.spv",
            "x86_use_edges.spv",
            "x86_liveness.spv",
            "x86_regalloc.spv",
            "x86_func_inst_counts.spv",
            "x86_func_inst_prefix_scan.spv",
            "x86_inst_plan.spv",
            "x86_encode.spv",
            "x86_elf_write.spv",
            "record_x86_elf_from_gpu_hir",
        ],
    );
    assert_contains_none(
        &compiler,
        "src/compiler.rs",
        &[
            "record_x86_from_gpu_token_buffer",
            "record_x86_from_wasm",
            "x86_from_wasm",
        ],
    );
    assert_contains_none(
        &x86_backend,
        "src/codegen/x86",
        &["wasm_body.spv", "wasm_functions.spv", "x86_from_wasm.spv"],
    );
}

#[test]
fn x86_backend_exposes_record_stage_boundaries() {
    let node_tree = repo_file("shaders/codegen/x86_node_tree_info.slang");
    let node_counts = repo_file("shaders/codegen/x86_node_inst_counts.slang");
    let node_order = repo_file("shaders/codegen/x86_node_inst_order.slang");
    let node_prefix = repo_file("shaders/codegen/x86_node_inst_prefix_scan.slang");
    let node_locations = repo_file("shaders/codegen/x86_node_inst_locations.slang");
    let node_gen = repo_file("shaders/codegen/x86_node_inst_gen.slang");
    let virtual_use = repo_file("shaders/codegen/x86_virtual_use_edges.slang");
    let virtual_liveness = repo_file("shaders/codegen/x86_virtual_liveness.slang");
    let virtual_regalloc = repo_file("shaders/codegen/x86_virtual_regalloc.slang");
    let lower = repo_file("shaders/codegen/x86_lower_values.slang");
    let use_edges = repo_file("shaders/codegen/x86_use_edges.slang");
    let liveness = repo_file("shaders/codegen/x86_liveness.slang");
    let regalloc = repo_file("shaders/codegen/x86_regalloc.slang");
    let counts = repo_file("shaders/codegen/x86_func_inst_counts.slang");
    let prefix = repo_file("shaders/codegen/x86_func_inst_prefix_scan.slang");
    let inst_plan = repo_file("shaders/codegen/x86_inst_plan.slang");
    let encode = repo_file("shaders/codegen/x86_encode.slang");
    let elf = repo_file("shaders/codegen/x86_elf_write.slang");

    assert_contains_all(
        &node_tree,
        "x86_node_tree_info.slang",
        &[
            "StructuredBuffer<uint> first_child",
            "StructuredBuffer<uint> next_sibling",
            "RWStructuredBuffer<uint4> x86_node_tree_record",
        ],
    );
    assert_contains_all(
        &node_counts,
        "x86_node_inst_counts.slang",
        &[
            "StructuredBuffer<uint4> x86_node_tree_record",
            "StructuredBuffer<uint> hir_stmt_record",
            "StructuredBuffer<uint> hir_expr_record",
            "RWStructuredBuffer<uint4> x86_node_inst_count_record",
            "RWStructuredBuffer<uint> x86_node_inst_scan_input",
        ],
    );
    assert_contains_all(
        &node_order,
        "x86_node_inst_order.slang",
        &[
            "StructuredBuffer<uint4> x86_node_tree_record",
            "StructuredBuffer<uint4> x86_node_inst_count_record",
            "RWStructuredBuffer<uint4> x86_node_inst_order_record",
            "RWStructuredBuffer<uint> x86_node_inst_scan_input",
        ],
    );
    assert_contains_all(
        &node_prefix,
        "x86_node_inst_prefix_scan.slang",
        &[
            "StructuredBuffer<uint4> x86_node_inst_order_record",
            "StructuredBuffer<uint> x86_node_inst_scan_local_prefix",
            "RWStructuredBuffer<uint4> x86_node_inst_range_record",
        ],
    );
    assert_contains_all(
        &node_locations,
        "x86_node_inst_locations.slang",
        &[
            "StructuredBuffer<uint> hir_kind",
            "StructuredBuffer<uint> hir_stmt_record",
            "StructuredBuffer<uint4> x86_node_inst_count_record",
            "StructuredBuffer<uint4> x86_node_inst_range_record",
            "RWStructuredBuffer<uint4> x86_node_inst_location_record",
        ],
    );
    assert_contains_all(
        &node_gen,
        "x86_node_inst_gen.slang",
        &[
            "StructuredBuffer<uint4> x86_node_inst_range_record",
            "StructuredBuffer<uint4> x86_node_inst_location_record",
            "StructuredBuffer<uint> hir_stmt_record",
            "StructuredBuffer<uint> hir_expr_record",
            "RWStructuredBuffer<uint4> x86_virtual_inst_record",
            "RWStructuredBuffer<uint4> x86_node_value_record",
        ],
    );
    assert_contains_all(
        &virtual_use,
        "x86_virtual_use_edges.slang",
        &[
            "StructuredBuffer<uint4> x86_virtual_inst_record",
            "StructuredBuffer<uint4> x86_virtual_inst_args",
            "RWStructuredBuffer<uint> x86_virtual_use_key",
            "RWStructuredBuffer<uint> x86_virtual_use_value",
        ],
    );
    assert_contains_all(
        &virtual_liveness,
        "x86_virtual_liveness.slang",
        &[
            "StructuredBuffer<uint> x86_virtual_use_key",
            "StructuredBuffer<uint> x86_virtual_use_value",
            "RWStructuredBuffer<uint> x86_virtual_live_start",
            "RWStructuredBuffer<uint> x86_virtual_live_end",
        ],
    );
    assert_contains_all(
        &virtual_regalloc,
        "x86_virtual_regalloc.slang",
        &[
            "StructuredBuffer<uint> x86_virtual_live_start",
            "StructuredBuffer<uint> x86_virtual_live_end",
            "RWStructuredBuffer<uint> x86_virtual_phys_reg",
        ],
    );
    assert_contains_all(
        &lower,
        "x86_lower_values.slang",
        &[
            "StructuredBuffer<uint> hir_expr_record",
            "StructuredBuffer<uint4> x86_func_return_stmt_record",
            "RWStructuredBuffer<uint> x86_vreg_kind",
            "RWStructuredBuffer<uint4> x86_vreg_args",
            "RWStructuredBuffer<uint> x86_expr_vreg",
            "RWStructuredBuffer<uint> x86_return_vreg",
        ],
    );
    assert_contains_all(
        &use_edges,
        "x86_use_edges.slang",
        &[
            "StructuredBuffer<uint4> x86_vreg_args",
            "RWStructuredBuffer<uint> x86_use_key",
            "RWStructuredBuffer<uint> x86_use_value",
        ],
    );
    assert_contains_all(
        &liveness,
        "x86_liveness.slang",
        &[
            "StructuredBuffer<uint> x86_use_key",
            "RWStructuredBuffer<uint> x86_live_start",
            "RWStructuredBuffer<uint> x86_live_end",
        ],
    );
    assert_contains_all(
        &regalloc,
        "x86_regalloc.slang",
        &[
            "StructuredBuffer<uint> x86_live_start",
            "StructuredBuffer<uint> x86_live_end",
            "RWStructuredBuffer<uint> x86_phys_reg",
        ],
    );
    assert_contains_all(
        &counts,
        "x86_func_inst_counts.slang",
        &[
            "RWStructuredBuffer<uint4> x86_func_inst_count_record",
            "RWStructuredBuffer<uint> x86_func_inst_count_status",
        ],
    );
    assert_contains_all(
        &prefix,
        "x86_func_inst_prefix_scan.slang",
        &[
            "StructuredBuffer<uint4> x86_func_inst_order_record",
            "RWStructuredBuffer<uint4> x86_func_inst_range_record",
        ],
    );
    assert_contains_all(
        &inst_plan,
        "x86_inst_plan.slang",
        &[
            "StructuredBuffer<uint4> x86_func_layout_record",
            "StructuredBuffer<uint> x86_entry_inst_status",
            "RWStructuredBuffer<uint> x86_select_plan",
        ],
    );
    assert_contains_all(
        &encode,
        "x86_encode.slang",
        &[
            "StructuredBuffer<uint> x86_inst_kind",
            "StructuredBuffer<uint> x86_inst_byte_offset",
            "RWStructuredBuffer<uint> x86_text_words",
        ],
    );
    assert_contains_all(
        &elf,
        "x86_elf_write.slang",
        &[
            "StructuredBuffer<uint> x86_text_words",
            "StructuredBuffer<uint> x86_elf_layout",
            "RWStructuredBuffer<uint> out_words",
        ],
    );
}

#[test]
fn x86_backend_has_no_token_source_or_callee_shape_recognizers() {
    let codegen_dir = repo_path("shaders/codegen");
    let shader_forbidden = [
        "ByteAddressBuffer",
        "source_bytes",
        "source_at",
        "token_words",
        "token_kind",
        "TokenKind",
        "token_text",
        "token_text_eq",
        "same_text",
        "RETURN_EVAL",
        "return_eval",
        "extract_expr",
        "extract_return",
        "extract_terminal",
        "lower_return_direct_call",
        "X86_VREG_CALL_DIRECT_I32",
        "NESTED_PARAM",
        "PARAM_COND_BRANCH",
        "CONST_OR_CALLEE",
        "PARAM_IMM_NEG_BRANCH",
        "PARAM_PARAM_BRANCH",
        "COMPARE_AND_COMPARE",
        "MOD_POW2",
        "LIMIT_BRANCH",
        "CHAIN",
        "core::i32",
        "core::bool",
        "core::u32",
        "core::u8",
        "u32::",
        "u8::",
        "wrapping_add",
        "wrapping_mul",
        "saturating_add",
        "saturating_mul",
        "between_inclusive",
        "select_i32",
        "from_i32",
        "to_i32",
    ];

    for path in slang_files(&codegen_dir).into_iter().filter(|path| {
        path.file_stem()
            .is_some_and(|stem| stem.to_string_lossy().starts_with("x86"))
    }) {
        let source = fs::read_to_string(&path)
            .unwrap_or_else(|err| panic!("read {}: {err}", path.display()));
        for forbidden in shader_forbidden {
            assert!(
                !source.contains(forbidden),
                "{} contains forbidden x86 backend pattern {forbidden:?}",
                path.display()
            );
        }
    }

    for rel in [
        "src/codegen/x86.rs",
        "src/codegen/x86/record.rs",
        "src/codegen/x86/record_init.rs",
        "src/codegen/x86/record_retained_expr.rs",
        "src/codegen/x86/finish.rs",
        "src/codegen/x86/support.rs",
    ] {
        let source = repo_file(rel);
        for forbidden in [
            "record_x86_from_gpu_token_buffer",
            "x86_from_wasm",
            "RETURN_EVAL",
            "return_eval",
            "extract_return",
            "extract_terminal",
            "lower_return_direct_call",
            "X86_VREG_CALL_DIRECT_I32",
        ] {
            assert!(
                !source.contains(forbidden),
                "{rel} contains forbidden x86 backend pattern {forbidden:?}",
            );
        }
    }
}
