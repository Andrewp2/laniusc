mod common;

use std::path::PathBuf;

use laniusc_compiler::compiler::CompileError;

#[test]
fn wasm_hir_body_uses_fragment_count_scan_scatter_pipeline() {
    let functions_mark = include_str!("../shaders/codegen/wasm/hir/functions_mark.slang");
    let functions_reach = include_str!("../shaders/codegen/wasm/hir/functions_reach.slang");
    let functions_count = include_str!("../shaders/codegen/wasm/hir/functions_count.slang");
    let plan_functions = include_str!("../shaders/codegen/wasm/hir/body_plan_functions.slang");
    let validate_common =
        include_str!("../shaders/codegen/wasm/hir/body_plan_validate_common.slang");
    let validate = include_str!("../shaders/codegen/wasm/hir/body_plan_validate.slang");
    let validate_return =
        include_str!("../shaders/codegen/wasm/hir/body_plan_validate_return.slang");
    let validate_return_call =
        include_str!("../shaders/codegen/wasm/hir/body_plan_validate_return_call.slang");
    let validate_return_agg_call =
        include_str!("../shaders/codegen/wasm/hir/body_plan_validate_return_agg_call.slang");
    let validate_return_nested_call =
        include_str!("../shaders/codegen/wasm/hir/body_plan_validate_return_nested_call.slang");
    let validate_assign =
        include_str!("../shaders/codegen/wasm/hir/body_plan_validate_assign.slang");
    let validate_control =
        include_str!("../shaders/codegen/wasm/hir/body_plan_validate_control.slang");
    let validate_call = include_str!("../shaders/codegen/wasm/hir/body_plan_validate_call.slang");
    let validate_all = [
        validate_common,
        validate,
        validate_return,
        validate_return_call,
        validate_return_agg_call,
        validate_return_nested_call,
        validate_assign,
        validate_control,
        validate_call,
    ]
    .join("\n");
    let plan_collect = include_str!("../shaders/codegen/wasm/hir/body_plan_collect.slang");
    let plan = include_str!("../shaders/codegen/wasm/hir/body_plan.slang");
    let plan_agg_direct_call =
        include_str!("../shaders/codegen/wasm/hir/body_plan_agg_direct_call.slang");
    let plan_agg_struct = include_str!("../shaders/codegen/wasm/hir/body_plan_agg_struct.slang");
    let plan_arrays = include_str!("../shaders/codegen/wasm/hir/body_plan_arrays.slang");
    let common = include_str!("../shaders/codegen/wasm/hir/body_common.slang");
    let let_init_clear = include_str!("../shaders/codegen/wasm/hir/body_let_init_clear.slang");
    let let_init = include_str!("../shaders/codegen/wasm/hir/body_let_init.slang");
    let clear = include_str!("../shaders/codegen/wasm/hir/body_clear.slang");
    let counts = include_str!("../shaders/codegen/wasm/hir/body.slang");
    let scan_local = include_str!("../shaders/codegen/wasm/hir/body_scan_local.slang");
    let scan_blocks = include_str!("../shaders/codegen/wasm/hir/body_scan_blocks.slang");
    let agg_call_arg_counts =
        include_str!("../shaders/codegen/wasm/hir/body_agg_call_arg_counts.slang");
    let agg_call_arg_records =
        include_str!("../shaders/codegen/wasm/hir/body_agg_call_arg_records.slang");
    let agg_call_finalize =
        include_str!("../shaders/codegen/wasm/hir/body_agg_call_finalize.slang");
    let arg_byte_common = include_str!("../shaders/codegen/wasm/hir/body_arg_byte_common.slang");
    let body_status = include_str!("../shaders/codegen/wasm/hir/body_status.slang");
    let scatter = include_str!("../shaders/codegen/wasm/hir/body_scatter.slang");
    let scatter_expr_control =
        include_str!("../shaders/codegen/wasm/hir/body_scatter_expr_control.slang");
    let scatter_let_direct =
        include_str!("../shaders/codegen/wasm/hir/body_scatter_let_direct.slang");
    let scatter_direct_nested_call =
        include_str!("../shaders/codegen/wasm/hir/body_scatter_direct_nested_call.slang");
    let scatter_agg_direct_call =
        include_str!("../shaders/codegen/wasm/hir/body_scatter_agg_direct_call.slang");
    let scatter_agg_call_args =
        include_str!("../shaders/codegen/wasm/hir/body_scatter_agg_call_args.slang");
    let scatter_agg_copy = include_str!("../shaders/codegen/wasm/hir/body_scatter_agg_copy.slang");
    let scatter_return_agg_direct_call =
        include_str!("../shaders/codegen/wasm/hir/body_scatter_return_agg_direct_call.slang");
    let scatter_arrays = include_str!("../shaders/codegen/wasm/hir/body_scatter_arrays.slang");
    let agg_body = include_str!("../shaders/codegen/wasm/hir/agg_body.slang");
    let assert_module = include_str!("../shaders/codegen/wasm/hir/assert_module.slang");
    let module_status = include_str!("../shaders/codegen/wasm/module_status.slang");
    let module = include_str!("../shaders/codegen/wasm/module.slang");
    let backend = include_str!("../crates/laniusc-compiler/src/codegen/wasm.rs");

    assert!(
        functions_mark.contains("atomic_u32_add(body_plan, BODY_PLAN_MAIN_COUNT")
            && validate_all
                .contains("atomic_u32_add(wasm_func_return_count_by_token, owner_fn, 1u)")
            && plan_functions.contains("wasm_func_return_count_by_token[token_i] == 0u")
            && plan.contains("plan_aggregate_ok(")
            && plan.contains("BODY_PLAN_FINALIZE_SLOT_COUNT")
            && plan.contains("GroupMemoryBarrierWithGroupSync();")
            && plan.contains("final_body_plan_word(")
            && !plan.contains("linear_dispatch_id(tid) != 0u"),
        "WASM body planning should collect and validate HIR facts in parallel, then publish final aggregate slots by lane"
    );
    assert!(
        functions_mark.contains("wasm_func_decl_flag")
            && functions_mark.contains("atomic_u32_or(wasm_func_flag, token, 1u)")
            && functions_reach.contains("node_enclosing_fn_token(node)")
            && functions_reach.contains("call_fn_index[callee_token]")
            && functions_reach.contains("call_intrinsic_tag[callee_token] != 0u")
            && functions_count.contains("BODY_PLAN_FUNCTION_COUNT")
            && backend.contains("WASM_FUNCTION_REACHABILITY_ITERATIONS"),
        "WASM function emission should discover reachable functions from HIR/typechecker call metadata before scanning function slots"
    );
    assert!(
        !common.contains("scalar_body_plan(")
            && !plan.contains("scalar_body_plan(")
            && !counts.contains("scalar_body_plan("),
        "WASM body planning should not keep a single-lane HIR walk helper"
    );
    assert!(
        !common.contains("print_call_at_token(")
            && !common.contains("body_fragment_for_token(")
            && validate_all.contains("publish_fragment(")
            && counts.contains("Publish function wrapper fragments"),
        "WASM body fragments should be produced by HIR-node lanes, not token lanes searching HIR"
    );
    assert!(
        backend.contains("GpuWasmSemanticHirBuffers")
            && plan_collect.contains("StructuredBuffer<uint> hir_semantic_dense_node;")
            && plan_collect.contains("semantic_hir_row_for_node(")
            && !common.contains("hir_semantic_")
            && plan_collect.contains("collect_semantic_hir_shape(node)")
            && plan_collect.contains("atomic_u32_max(body_plan, BODY_PLAN_SEMANTIC_MAX_DEPTH"),
        "WASM body planning should consume the dense semantic-HIR tree needed for Pareas-shaped expression streams"
    );
    assert!(
        let_init_clear.contains("body_let_init_expr_by_decl_token[token_i] = INVALID;")
            && let_init.contains("body_let_init_expr_by_decl_token[decl_token] = init_expr;")
            && common.contains("body_let_init_expr_by_decl_token[decl_token]")
            && !common.contains("for (uint node = 0u; node < active_count; node += 1u)"),
        "WASM const evaluation should resolve let initializers through a parallel decl-token table"
    );
    assert!(
        validate_all.contains("STMT_RECORD_KIND_IF")
            && validate_all.contains("if_open_fragment_and_len(node, condition_node, open_len)")
            && common.contains("if_end_token_and_len(")
            && common.contains("if_else_token_and_len(")
            && validate_all.contains("BODY_FRAGMENT_IF_ELSE")
            && validate_all.contains("BODY_FRAGMENT_IF_END")
            && scatter_expr_control.contains("BODY_FRAGMENT_IF_OPEN_I32")
            && scatter_expr_control.contains("WASM_IF")
            && !validate_all.contains("if_condition_value(node, condition)")
            && !validate_all.contains("node_enabled_by_constant_if_chain(node)")
            && !common.contains("constant_if_selects_node("),
        "WASM body validation and emission should lower runtime if/else control from HIR records"
    );
    assert!(
        validate_all.contains("STMT_RECORD_KIND_WHILE")
            && validate_all.contains("while_open_fragment_and_len(node, condition_node, open_len)")
            && common.contains("while_close_token_and_len(")
            && validate_all.contains("BODY_FRAGMENT_WHILE_CLOSE")
            && scatter_expr_control.contains("BODY_FRAGMENT_WHILE_OPEN_I32")
            && scatter_expr_control.contains("expr_simple_byte("),
        "WASM body validation and emission should lower simple scalar while loops from HIR records and semantic expression tables"
    );
    assert!(
        validate_all.contains("STMT_RECORD_KIND_BREAK")
            && validate_all.contains("STMT_RECORD_KIND_CONTINUE")
            && validate_all.contains("loop_control_fragment_and_len(node, depth, len)")
            && common.contains("hir_nearest_loop_node")
            && common.contains("loop_control_branch_depth(")
            && scatter_expr_control.contains("BODY_FRAGMENT_BRANCH")
            && scatter_expr_control.contains("branch_fragment_byte("),
        "WASM body validation and emission should lower break/continue from parser-owned HIR control context"
    );
    assert!(
        validate_all.contains("STMT_RECORD_KIND_FOR")
            && validate_all.contains("for_open_range_fragment_and_len(")
            && validate_all.contains("for_close_token_and_len(")
            && validate_all.contains("BODY_FRAGMENT_FOR_CLOSE_RANGE_I32")
            && counts.contains("BODY_FRAGMENT_FUNCTION_END")
            && common.contains("numeric_range_iterable_for_for_node(")
            && common.contains("BODY_FRAGMENT_FOR_OPEN_RANGE_I32")
            && common.contains("BODY_FRAGMENT_FUNCTION_END")
            && scatter_expr_control.contains("for_open_range_i32_fragment_byte(")
            && scatter_expr_control.contains("for_close_range_i32_fragment_byte("),
        "WASM body validation and emission should lower numeric range for-loops from HIR records"
    );
    assert!(
        counts.contains("function_end_token(")
            && scatter.contains("WASM_RETURN")
            && scatter.contains("WASM_UNREACHABLE")
            && scatter.contains("BODY_FRAGMENT_FUNCTION_END"),
        "WASM body emission should encode HIR returns as explicit return instructions and close functions with an unreachable fallthrough"
    );
    assert!(
        clear.contains("body_fragment_len[token_i] = 0u;")
            && clear.contains("body_fragment_aux[token_i] = uint4(INVALID, 0u, 0u, 0u);")
            && validate_all.contains("RWStructuredBuffer<uint4> body_fragment_aux;")
            && validate_all.contains("direct_call_aux(")
            && counts.contains("body_fragment_aux[slot] = uint4(INVALID, 0u, 0u, 0u);"),
        "WASM body record producers should publish fragment lengths, metadata, and auxiliary call records after a parallel token clear"
    );
    assert!(
        validate_all.contains("uint slot = token_i * 2u;")
            && counts.contains("end_token * 2u + 1u")
            && backend.contains("let body_item_capacity = token_capacity.saturating_mul(2);"),
        "WASM body record producers should publish ordered fragment slots with room for synthetic post-token records"
    );
    assert!(
        scan_local.contains("prefix_scan_u32_256(lane, value)"),
        "WASM body offsets should use the shared local prefix-scan primitive"
    );
    assert!(
        scan_blocks.contains("block_prefix_scan_step<uint, PrefixScanU32Add>"),
        "WASM body offsets should scan block totals with the shared block-scan primitive"
    );
    assert!(
        scatter.contains("global_exclusive_prefix(")
            && scatter_let_direct.contains("global_exclusive_prefix(")
            && scatter.contains("body_words[offset + byte_i] = fragment_byte(meta, len, byte_i);")
            && scatter_let_direct.contains("body_fragment_aux[token_i]")
            && scatter_let_direct.contains("for (uint i = 0u; i < arg_count; i += 1u)")
            && scatter_let_direct.contains("let_direct_call_i32_fragment_byte(")
            && scatter_let_direct.contains("return_direct_call_i32_fragment_byte(")
            && scatter_let_direct.contains("print_direct_call_i64_fragment_byte(")
            && scatter_let_direct.contains("BODY_FRAGMENT_RETURN_DIRECT_CALL_I32")
            && scatter_let_direct.contains("BODY_FRAGMENT_LET_DIRECT_CALL_I32")
            && scatter_let_direct.contains("BODY_FRAGMENT_PRINT_DIRECT_CALL_I64")
            && scatter_let_direct.contains("BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32")
            && scatter_let_direct.contains("BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32")
            && scatter_let_direct.contains("assign_compound_direct_call_i32_fragment_byte(")
            && scatter_let_direct.contains("body_words[offset + byte_i]")
            && backend.contains("features.has(WASM_BODY_FEATURE_DIRECT)")
            && !scatter.contains("for (uint byte_i = 0u; byte_i < len; byte_i += 1u)")
            && !scatter_let_direct.contains("for (uint byte_i = 0u; byte_i < len; byte_i += 1u)")
            && !scatter.contains("accept_body_status(")
            && !scatter.contains("reject_capacity("),
        "WASM body scatter should place fragment bytes with per-byte-slot lanes from fragment records"
    );
    assert!(
        !validate_return_call.contains("return_direct_call_nested_arg")
            && !validate_return_call.contains("aux.w = ((nested_arg_count + 1u) & 0xffu)")
            && validate_return_call.contains("return_binary_direct_call_fragment_and_len(")
            && validate_return_call.contains("BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32")
            && !scatter_let_direct.contains("MAX_EXPR_EMIT_STACK"),
        "WASM scalar return-call validation should not carry nested-call planning or capped argument ordinals"
    );
    assert!(
        backend.contains("hir_body_scatter_direct_nested_call_pass")
            && backend.contains("hir_body_plan_validate_return_call_pass")
            && backend
                .contains("record.body_plan.dispatch.hir_body_plan_validate_return_call.start")
            && backend.contains("hir_body_plan_validate_return_nested_call_pass")
            && backend.contains(
                "record.body_plan.dispatch.hir_body_plan_validate_return_nested_call.start"
            )
            && backend.contains("features.has(WASM_BODY_FEATURE_RETURN_DIRECT)")
            && backend.contains("features.has(WASM_BODY_FEATURE_LET_DIRECT)")
            && backend.contains("record.phase2.dispatch.hir_body_scatter_direct_nested_call.start")
            && backend.contains("features.has(WASM_BODY_FEATURE_RETURN_NESTED_DIRECT)")
            && validate_return_nested_call.contains("aux.w = nested_arg_ordinal + 1u;")
            && validate_return_nested_call.contains("BODY_FEATURE_RETURN_NESTED_DIRECT")
            && scatter_direct_nested_call.contains("global_exclusive_prefix(")
            && scatter_direct_nested_call
                .contains("meta.x != BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 || aux.w == 0u")
            && scatter_direct_nested_call.contains("direct_call_expr_byte_with_nested_arg(")
            && scatter_direct_nested_call.contains("body_words[offset + byte_i]")
            && !scatter_let_direct.contains("member_result_field_node[member_name]")
            && !scatter_let_direct.contains("direct_call_expr_byte_with_nested_arg("),
        "WASM return nested-direct byte patching should live in a gated byte-lane scatter pass"
    );
    assert!(
        backend.contains("hir_body_plan_agg_direct_call_pass")
            && backend.contains("hir_body_plan_agg_struct_pass")
            && backend.contains("hir_body_agg_call_arg_counts_pass")
            && backend.contains("hir_body_agg_call_arg_records_pass")
            && backend.contains("hir_body_agg_call_finalize_pass")
            && backend.contains("hir_body_scatter_agg_call_args_pass")
            && backend.contains("hir_body_scatter_agg_direct_call_pass")
            && backend.contains("features.has(WASM_BODY_FEATURE_LET_AGG_DIRECT)")
            && backend.contains("features.has(WASM_BODY_FEATURE_AGG_COPY)")
            && backend.contains("features.has(WASM_BODY_FEATURE_ARRAY_ALLOC)")
            && backend.contains("features.has(WASM_BODY_FEATURE_MEMBER_EXPR)")
            && backend.contains("features.has(WASM_BODY_FEATURE_ARRAYS)")
            && backend.contains("features.has(WASM_BODY_FEATURE_RETURN_AGG_DIRECT)")
            && backend.contains("record.body_plan.dispatch.hir_body_plan_agg_direct_call.start")
            && backend.contains("record.body_plan.dispatch.hir_body_plan_agg_struct.start")
            && backend.contains("record.body_plan.dispatch.hir_body_agg_call_arg_counts.start")
            && backend
                .contains("record.body_plan.dispatch.hir_body_agg_call_arg_count_scan_local.start")
            && backend.contains("record.body_plan.dispatch.hir_body_agg_call_arg_records.start")
            && backend
                .contains("record.body_plan.dispatch.hir_body_agg_call_arg_byte_scan_local.start")
            && backend.contains("record.body_plan.dispatch.hir_body_agg_call_finalize.start")
            && !backend.contains("record.phase2.dispatch.hir_body_agg_call_arg_counts.start")
            && !backend
                .contains("record.phase2.dispatch.hir_body_agg_call_arg_records.start")
            && backend.contains("record.phase2.dispatch.hir_body_scatter_agg_call_args.start")
            && backend.contains("record.phase2.dispatch.hir_body_scatter_agg_direct_call.start")
            && backend.contains("record.phase2.dispatch.hir_body_scatter_agg_copy.start")
            && backend.contains(
                "record.phase2.dispatch.hir_body_scatter_return_agg_direct_call.start"
            )
            && backend.contains("hir_body_plan_validate_return_agg_call_pass")
            && backend.contains(
                "record.body_plan.dispatch.hir_body_plan_validate_return_agg_call.start"
            )
            && validate_return_agg_call.contains("BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32")
            && !validate_return_agg_call.contains("for (uint i = 0u; i < arg_count; i += 1u)")
            && validate_return_agg_call.contains("call_tail_len")
            && plan_collect.contains("BODY_FEATURE_ARRAY_ALLOC")
            && plan_collect.contains("BODY_FEATURE_AGG_COPY")
            && !plan_agg_direct_call.contains("for (uint i = 0u; i < arg_count; i += 1u)")
            && plan_agg_direct_call.contains("call_set_tail_len")
            && plan_agg_direct_call.contains("BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32")
            && plan_agg_direct_call.contains("BODY_FRAGMENT_AGG_DIRECT_COPY_I32")
            && plan_agg_struct.contains("BODY_FRAGMENT_LET_ARRAY_I32")
            && plan_agg_struct.contains("BODY_FRAGMENT_AGG_FIELD_STORE_I32")
            && plan_agg_struct.contains("struct_init_field_ordinal_by_node")
            && !plan_arrays.contains("account_let_struct_literal(node, owner_fn, token)")
            && !plan_arrays.contains("account_let_aggregate_direct_call(node, owner_fn, token)")
            && !plan_arrays.contains("account_struct_field_store(node, owner_fn, token)")
            && agg_call_arg_counts.contains("wasm_agg_call_arg_count_by_fragment[fragment_i]")
            && agg_call_arg_records.contains("fragment_for_arg_record(record_i")
            && agg_call_arg_records.contains("direct_call_abi_arg_node(call_node, fn_token, ordinal)")
            && agg_call_arg_records.contains("wasm_agg_call_arg_len[record_i] = len;")
            && agg_call_arg_records.contains("atomic_u32_add(wasm_func_invalid_count_by_token")
            && agg_call_finalize.contains("arg_bytes_for_fragment(fragment_i)")
            && agg_call_finalize.contains("body_fragment_len[fragment_i] = new_len;")
            && agg_call_finalize.contains("atomic_u32_add(wasm_func_body_len_by_token")
            && scatter_agg_call_args.contains("import body_arg_byte_common;")
            && !scatter_agg_call_args.contains("import body_common;")
            && arg_byte_common.contains("direct_call_abi_arg_byte(")
            && arg_byte_common.contains("aggregate_address_expr_byte(")
            && scatter_agg_call_args.contains("record_for_arg_byte(")
            && scatter_agg_call_args.contains("direct_call_abi_arg_byte(")
            && scatter_agg_call_args.contains("body_words[body_byte_i]")
            && scatter_agg_direct_call.contains("arg_bytes_for_fragment(token_i)")
            && scatter_agg_direct_call.contains("body_words[body_byte_i]")
            && scatter_agg_direct_call.contains("meta.x != BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32")
            && !scatter_agg_direct_call.contains("for (uint i = 0u; i < arg_count; i += 1u)")
            && !scatter_agg_direct_call.contains("BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32")
            && scatter_return_agg_direct_call.contains("BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32")
            && scatter_return_agg_direct_call.contains("return_agg_direct_call_i32_fragment_byte(")
            && scatter_return_agg_direct_call.contains("arg_bytes_for_fragment(token_i)")
            && !scatter_return_agg_direct_call.contains("for (uint i = 0u; i < arg_count; i += 1u)")
            && scatter_agg_copy.contains("BODY_FRAGMENT_LET_ARRAY_I32")
            && scatter_agg_copy.contains("BODY_FRAGMENT_AGG_DIRECT_COPY_I32")
            && scatter_agg_copy.contains("aggregate_direct_copy_i32_fragment_byte(")
            && !scatter_arrays.contains("WASM_MAX_DIRECT_CALL_ARGS")
            && scatter_agg_direct_call.contains("global_exclusive_prefix("),
        "WASM aggregate direct-call byte paths should use recorded argument counts and keep return aggregate direct calls out of the heavy let-aggregate override"
    );
    assert!(
        body_status.contains("BODY_STATUS_SLOT_COUNT")
            && body_status.contains("GroupMemoryBarrierWithGroupSync();")
            && body_status.contains("body_status[0u] = ok ? total_len : 0u;")
            && body_status.contains("status[2u] = ok ? 0u : ERR_UNSUPPORTED_SOURCE_SHAPE;"),
        "WASM body status should be published by status-slot lanes before scatter"
    );
    assert!(
        module_status.contains("MODULE_STATUS_SLOT_COUNT")
            && module_status.contains("GroupMemoryBarrierWithGroupSync();")
            && module_status.contains("status[0u] = module_len;")
            && module_status.contains("status[1u] = ok ? 3u : 0u;")
            && module.contains("StructuredBuffer<uint> status;")
            && !module.contains("if (linear_dispatch_id(tid) == 0u)")
            && !module.contains("RWStructuredBuffer<uint> status;"),
        "WASM module status should be published by status-slot lanes before module byte emission"
    );
    assert!(
        agg_body.contains("StructuredBuffer<uint> status;")
            && assert_module.contains("StructuredBuffer<uint> status;")
            && !agg_body.contains("RWStructuredBuffer<uint> status;")
            && !assert_module.contains("RWStructuredBuffer<uint> status;")
            && !agg_body.contains("target == 0u")
            && !assert_module.contains("target == 0u")
            && !agg_body.contains("status[2u] = 0u;")
            && !assert_module.contains("status[2u] = 0u;"),
        "placeholder WASM passes should stay read-only until they are rebuilt as record-driven emitters"
    );
    assert!(
        backend.contains("record.dispatch.hir_body_plan_collect.start")
            && backend.contains("record.dispatch.hir_functions_reach")
            && backend.contains("record.dispatch.hir_functions_count.start")
            && backend.contains("record.dispatch.hir_body_let_init_clear.start")
            && backend.contains("record.dispatch.hir_body_let_init.start")
            && backend.contains("record.body_plan.dispatch.hir_body_plan_validate.start")
            && backend.contains("record.body_plan.dispatch.hir_body_plan_finalize.start")
            && backend.contains("record.body_plan.dispatch.hir_body_clear.start")
            && backend.contains("record.body_plan.dispatch.hir_body_counts.start")
            && backend.contains("record.body_plan.dispatch.hir_body_scan_local.start")
            && backend.contains("record.body_plan.dispatch.hir_body_scan_blocks")
            && backend.contains("record.body_plan.dispatch.hir_body_status.start")
            && backend.contains("record.phase2.dispatch.hir_body_scatter.start")
            && backend.contains("record.phase2.dispatch.module_status.start")
            && backend.contains("WASM_BODY_PLAN_FINALIZE_GROUPS")
            && backend.contains("WASM_BODY_STATUS_GROUPS")
            && backend.contains("WASM_MODULE_STATUS_GROUPS")
            && backend.contains("WASM_BODY_PLAN_WORDS * 4")
            && !backend.contains("dispatch_workgroups(1, 1, 1)"),
        "WASM backend should record body emission as let-init table -> plan collect -> clear -> validate -> finalize -> counts -> scan -> scatter"
    );

    let let_init_clear_pos = backend
        .find("record.dispatch.hir_body_let_init_clear.start")
        .expect("body let-init clear dispatch should be recorded");
    let functions_mark_pos = backend
        .find("record.dispatch.hir_functions_mark.start")
        .expect("function mark dispatch should be recorded");
    let functions_reach_pos = backend
        .find("record.dispatch.hir_functions_reach")
        .expect("function reachability dispatch should be recorded");
    let functions_count_pos = backend
        .find("record.dispatch.hir_functions_count.start")
        .expect("function count dispatch should be recorded");
    let func_scan_pos = backend
        .find("record.dispatch.hir_func_scan_local.start")
        .expect("function scan dispatch should be recorded");
    let let_init_pos = backend
        .find("record.dispatch.hir_body_let_init.start")
        .expect("body let-init dispatch should be recorded");
    let collect_pos = backend
        .find("record.dispatch.hir_body_plan_collect.start")
        .expect("body-plan collect dispatch should be recorded");
    let validate_pos = backend
        .find("record.body_plan.dispatch.hir_body_plan_validate.start")
        .expect("body-plan validate dispatch should be recorded");
    let validate_done_pos = backend
        .find("record.body_plan.dispatch.hir_body_plan_validate.done")
        .expect("body-plan validate completion should be recorded");
    let validate_dispatch = &backend[validate_pos..validate_done_pos];
    assert!(
        validate_dispatch
            .contains("compute.dispatch_workgroups(hir_node_groups_x, hir_node_groups_y, 1);"),
        "WASM body-plan validation must dispatch over HIR nodes so expression and statement fragments are all published"
    );
    let finalize_pos = backend
        .find("record.body_plan.dispatch.hir_body_plan_finalize.start")
        .expect("body-plan finalize dispatch should be recorded");
    let counts_pos = backend
        .find("record.body_plan.dispatch.hir_body_counts.start")
        .expect("body-counts dispatch should be recorded");
    let clear_pos = backend
        .find("record.body_plan.dispatch.hir_body_clear.start")
        .expect("body-clear dispatch should be recorded");
    let body_status_pos = backend
        .find("record.body_plan.dispatch.hir_body_status.start")
        .expect("body-status dispatch should be recorded");
    let scatter_pos = backend
        .find("record.phase2.dispatch.hir_body_scatter.start")
        .expect("body-scatter dispatch should be recorded");
    let enum_match_pos = backend
        .find("record.phase2.dispatch.hir_enum_match_records.start")
        .expect("enum-match dispatch should be recorded");
    let module_status_pos = backend
        .find("record.phase2.dispatch.module_status.start")
        .expect("module-status dispatch should be recorded");
    let module_pos = backend
        .find("record.phase2.dispatch.module.start")
        .expect("module dispatch should be recorded");
    assert!(
        functions_mark_pos < functions_reach_pos
            && functions_reach_pos < functions_count_pos
            && functions_count_pos < func_scan_pos
            && let_init_clear_pos < let_init_pos
            && let_init_pos < collect_pos
            && collect_pos < clear_pos
            && clear_pos < validate_pos
            && validate_pos < finalize_pos
            && finalize_pos < counts_pos
            && counts_pos < body_status_pos
            && body_status_pos < scatter_pos,
        "WASM body-plan dispatches should run before body counts in pipeline order"
    );
    assert!(
        scatter_pos < enum_match_pos
            && enum_match_pos < module_status_pos
            && module_status_pos < module_pos,
        "WASM module status should be published after body scatter and before module byte emission"
    );
}

#[test]
fn wasm_executes_scalar_constant_return_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
const BASE: i32 = 7;

fn main() {
    return BASE + 35;
}
"#,
    )
    .expect("scalar constant-return source should compile to WASM");

    let status =
        common::run_wasm_main_return_with_node("scalar WASM main return", "scalar_return", &wasm);
    assert_eq!(status, 42);
}

#[test]
fn wasm_executes_intrinsic_print_stdout_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    print(6 * 7);
    print(-7);
    return 0;
}
"#,
    )
    .expect("intrinsic print source should compile to WASM");

    let stdout = common::run_wasm_main_with_node("WASM intrinsic print", "intrinsic_print", &wasm);
    assert_eq!(stdout, "42\n-7\n");
}

#[test]
fn wasm_executes_std_io_write_stdout_import_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::io;

fn main() -> i32 {
    let written: i32 = std::io::write_stdout(0, 0);
    if (written != 0) {
        return 1;
    }
    return 0;
}
"#,
    ])
    .expect("std::io write_stdout import should compile to WASM");

    let stdout =
        common::run_wasm_main_with_node("WASM std::io write_stdout", "stdio_write_stdout", &wasm);
    assert_eq!(stdout, "");
}

#[test]
fn wasm_executes_std_io_write_stdout_bytes_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/mem.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import core::mem;
import std::io;

fn main() -> i32 {
    let bytes: [i32; 1] = [65];
    let ptr: u32 = core::mem::i32_array_data_ptr(bytes);
    let written: i32 = std::io::write_stdout(ptr, 1);
    if (written != 1) {
        return 1;
    }
    return 0;
}
"#,
    ])
    .expect("std::io write_stdout byte buffer should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM std::io write_stdout bytes",
        "stdio_write_bytes",
        &wasm,
    );
    assert_eq!(stdout, "A");
}

#[test]
fn wasm_executes_std_process_argc_import_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/process.lani"),
        r#"
module app::main;

import std::process;

fn main() -> i32 {
    let count: i32 = std::process::argc();
    if (count != 2) {
        return 7;
    }
    return 0;
}
"#,
    ])
    .expect("std::process argc import should compile to WASM");

    let status =
        common::run_wasm_main_return_with_node("WASM std::process argc", "process_argc", &wasm);
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_std_process_argument_read_imports_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/mem.lani"),
        include_str!("../stdlib/std/io.lani"),
        include_str!("../stdlib/std/process.lani"),
        r#"
module app::main;

import core::mem;
import std::io;
import std::process;

fn main() -> i32 {
    let buffer: [i32; 2] = [0, 0];
    let ptr: u32 = core::mem::i32_array_data_ptr(buffer);
    let count: i32 = std::process::argc();
    let len: i32 = std::process::arg_len(0);
    let copied: i32 = std::process::arg_read(0, ptr, len);
    if (count != 2) {
        return 1;
    }
    if (len != 7) {
        return 2;
    }
    if (copied != len) {
        return 3;
    }
    let written: i32 = std::io::write_stdout(ptr, copied);
    if (written != copied) {
        return 4;
    }
    return 0;
}
"#,
    ])
    .expect("std::process argument read imports should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM std::process argument read",
        "process_argument_read",
        &wasm,
    );
    assert_eq!(stdout, "program");
}

#[test]
fn wasm_executes_std_random_and_time_imports_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/random.lani"),
        include_str!("../stdlib/std/time.lani"),
        r#"
module app::main;

import std::random;
import std::time;

fn main() -> i32 {
    let random_value: u32 = std::random::secure_u32();
    let seconds: i32 = std::time::unix_seconds();
    if (random_value != 1234567) {
        return 1;
    }
    if (seconds != 1234567890) {
        return 2;
    }
    return 0;
}
"#,
    ])
    .expect("std::random and std::time imports should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM std::random and std::time",
        "random_time",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_alloc_allocator_alloc_dealloc_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        r#"
module app::main;

import alloc::allocator;

fn main() -> i32 {
    let ptr: u32 = alloc::allocator::alloc(64, 8);
    if (ptr == 0) {
        return 1;
    }
    alloc::allocator::dealloc(ptr, 64, 8);
    return 0;
}
"#,
    ])
    .expect("alloc::allocator alloc/dealloc imports should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM alloc::allocator alloc/dealloc",
        "alloc_allocator_alloc_dealloc",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_host_runtime_smoke_source_pack_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/alloc/allocator.lani"),
        include_str!("../stdlib/std/env.lani"),
        include_str!("../stdlib/std/io.lani"),
        include_str!("../stdlib/std/process.lani"),
        include_str!("../stdlib/std/random.lani"),
        include_str!("../stdlib/std/time.lani"),
        include_str!("../sample_programs/host_runtime_smoke.lani"),
    ])
    .expect("host runtime smoke source pack should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM host runtime smoke source pack",
        "host_runtime_smoke_source_pack",
        &wasm,
    );
    assert_eq!(stdout, "99\n");
}

#[test]
fn wasm_executes_std_env_imports_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/mem.lani"),
        include_str!("../stdlib/std/env.lani"),
        r#"
module app::main;

import core::mem;
import std::env;

fn main() -> i32 {
    let buffer: [i32; 8] = [0, 0, 0, 0, 0, 0, 0, 0];
    let ptr: u32 = core::mem::i32_array_data_ptr(buffer);
    let cwd_len: i32 = std::env::current_dir_read(ptr, 64);
    if (cwd_len <= 0) {
        return 1;
    }

    let count: i32 = std::env::var_count();
    if (count != 1) {
        return 2;
    }

    let key_len: i32 = std::env::var_key_len(0);
    if (key_len <= 0) {
        return 3;
    }
    let key_read: i32 = std::env::var_key_read(0, ptr, 64);
    if (key_read != key_len) {
        return 4;
    }

    let value_len: i32 = std::env::var_len(ptr, key_len);
    if (value_len <= 0) {
        return 5;
    }
    let value_read: i32 = std::env::var_read(ptr, key_len, ptr, 64);
    if (value_read != value_len) {
        return 6;
    }

    return 0;
}
"#,
    ])
    .expect("std::env imports should compile to WASM");

    let status = common::run_wasm_main_return_with_node("WASM std::env", "env_imports", &wasm);
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_std_fs_file_io_imports_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/mem.lani"),
        include_str!("../stdlib/std/fs.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import core::mem;
import std::fs;
import std::io;

fn main() -> i32 {
    let path: [i32; 1] = [102];
    let payload: [i32; 1] = [82];
    let read_buffer: [i32; 1] = [0];
    let path_ptr: u32 = core::mem::i32_array_data_ptr(path);
    let payload_ptr: u32 = core::mem::i32_array_data_ptr(payload);
    let read_ptr: u32 = core::mem::i32_array_data_ptr(read_buffer);

    let output: i32 = std::fs::open_write(path_ptr, 1);
    if (output < 0) {
        return 1;
    }
    let written: i32 = std::fs::write(output, payload_ptr, 1);
    if (written != 1) {
        return 2;
    }
    let output_closed: i32 = std::fs::close(output);
    if (output_closed < 0) {
        return 3;
    }

    let input: i32 = std::fs::open_read(path_ptr, 1);
    if (input < 0) {
        return 4;
    }
    let read_count: i32 = std::fs::read(input, read_ptr, 1);
    if (read_count != 1) {
        return 5;
    }
    let input_closed: i32 = std::fs::close(input);
    if (input_closed < 0) {
        return 6;
    }
    let copied: i32 = std::io::write_stdout(read_ptr, 1);
    if (copied != 1) {
        return 7;
    }
    return 0;
}
"#,
    ])
    .expect("std::fs low-level file imports should compile to WASM");

    let stdout = common::run_wasm_main_with_node("WASM std::fs file IO", "fs_file_io", &wasm);
    assert_eq!(stdout, "R");
}

#[test]
fn wasm_executes_std_fs_path_text_write_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/fs.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::fs;
import std::io;

fn main() -> i32 {
    let file: std::fs::FileHandle = std::fs::open_write_path("wasm_text.txt");
    if (file < 0) {
        return 1;
    }
    let written: i32 = std::io::write_text(file, "saved");
    let closed: i32 = std::fs::close_file(file);
    if (written != 5) {
        return 2;
    }
    if (closed != 0) {
        return 3;
    }
    return 0;
}
"#,
    ])
    .expect("std::fs path text write should compile to WASM");

    let result = common::run_wasm_main_with_node_and_files(
        "WASM std::fs path text write",
        "std_fs_path_text_write",
        &wasm,
        &[],
    );
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stdout, "");
    assert_eq!(
        result.files.get("wasm_text.txt").map(Vec::as_slice),
        Some(b"saved".as_slice())
    );
}

#[test]
fn wasm_executes_std_fs_path_text_write_decodes_escapes_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/fs.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::fs;
import std::io;

fn main() -> i32 {
    let file: std::fs::FileHandle = std::fs::open_write_path("escaped_text.txt");
    if (file < 0) {
        return 1;
    }
    let written: i32 = std::io::write_text(file, "line\nnext");
    let closed: i32 = std::fs::close_file(file);
    if (written != 9) {
        return 2;
    }
    if (closed != 0) {
        return 3;
    }
    return 0;
}
"#,
    ])
    .expect("std::fs path text write with escapes should compile to WASM");

    let result = common::run_wasm_main_with_node_and_files(
        "WASM std::fs path text write escape decode",
        "std_fs_path_text_write_escape_decode",
        &wasm,
        &[],
    );
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stdout, "");
    assert_eq!(
        result.files.get("escaped_text.txt").map(Vec::as_slice),
        Some(b"line\nnext".as_slice())
    );
}

#[test]
fn wasm_executes_std_fs_path_i32_roundtrip_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/std/fs.lani"),
        include_str!("../stdlib/std/io.lani"),
        r#"
module app::main;

import std::fs;
import std::io;

fn main() -> i32 {
    let output: std::fs::FileHandle = std::fs::open_write_path("wasm_i32.txt");
    if (output < 0) {
        return 1;
    }
    let write_value: i32 = std::io::write_i32(output, 12345);
    let write_line: i32 = std::io::write_newline(output);
    let output_close: i32 = std::fs::close_file(output);
    if (write_value < 0) {
        return 2;
    }
    if (write_line < 0) {
        return 6;
    }
    if (output_close < 0) {
        return 7;
    }

    let input: std::fs::FileHandle = std::fs::open_read_path("wasm_i32.txt");
    if (input < 0) {
        return 3;
    }
    let value: i32 = std::fs::read_i32(input, -1);
    let input_close: i32 = std::fs::close_file(input);
    if (input_close < 0) {
        return 4;
    }
    if (value != 12345) {
        return 5;
    }

    std::io::print_i32(value);
    return 0;
}
"#,
    ])
    .expect("std::fs path i32 roundtrip should compile to WASM");

    let result = common::run_wasm_main_with_node_and_files(
        "WASM std::fs path i32 roundtrip",
        "std_fs_path_i32_roundtrip",
        &wasm,
        &[],
    );
    assert_eq!(result.exit_code, 0);
    assert_eq!(result.stdout, "12345\n");
    assert_eq!(
        result.files.get("wasm_i32.txt").map(Vec::as_slice),
        Some(b"12345\n".as_slice())
    );
}

#[test]
fn wasm_executes_scalar_local_assignments_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let x: i32 = 10;
    x += 5;
    x -= 3;
    x *= 4;
    x /= 6;
    x %= 5;
    print(x);
    return 0;
}
"#,
    )
    .expect("scalar local assignments should compile to WASM");

    let stdout =
        common::run_wasm_main_with_node("WASM scalar local assignments", "local_assigns", &wasm);
    assert_eq!(stdout, "3\n");
}

#[test]
fn wasm_executes_scalar_local_return_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let x: i32 = 10;
    x += 5;
    return x;
}
"#,
    )
    .expect("scalar local return should compile to WASM");

    let status =
        common::run_wasm_main_return_with_node("WASM scalar local return", "local_return", &wasm);
    assert_eq!(status, 15);
}

#[test]
fn wasm_executes_f32_literal_local_with_node() {
    common::require_node();
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/wasm/f32_literal_local.lani");
    let wasm = common::compile_path_to_wasm_with_timeout(&source)
        .expect("f32 literal locals should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM f32 literal local",
        "f32_literal_local",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_f32_scalar_function_with_node() {
    common::require_node();
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/wasm/f32_scalar_function.lani");
    let wasm = common::compile_path_to_wasm_with_timeout(&source)
        .expect("f32 scalar functions should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM f32 scalar function",
        "f32_scalar_function",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_struct_local_member_reads_with_node() {
    common::require_node();
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/wasm/struct_local_member.lani");
    let wasm = common::compile_path_to_wasm_with_timeout(&source)
        .expect("struct literal locals and member reads should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM struct local member reads",
        "struct_local_member",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_aggregate_receiver_f32_member_call_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn x_value(self) -> f32 {
        return self.x;
    }
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 4.0, y: 1.0, z: 2.0 };
    let x: f32 = value.x_value();
    if (x > 3.5) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("aggregate receiver f32 member call should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate receiver f32 member call",
        "aggregate_receiver_f32_member_call",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_f32_aggregate_member_binary_return_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 2.0, y: 3.0, z: 4.0 };
    let result: f32 = value.dot(value);
    if (result > 28.9 && result < 29.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("f32 aggregate member binary return should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM f32 aggregate member binary return",
        "f32_aggregate_member_binary_return",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_nested_f32_direct_call_argument_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn x_value(self) -> f32 {
        return self.x;
    }

    fn half_x(self) -> f32 {
        return half(self.x_value());
    }
}

fn half(value: f32) -> f32 {
    return value / 2.0;
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 2.0, y: 0.0, z: 0.0 };
    let result: f32 = value.half_x();
    if (result > 0.9 && result < 1.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("nested f32 direct call arguments should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM nested f32 direct call argument",
        "nested_f32_direct_call_argument",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_aggregate_return_method_with_f32_receiver_call_local() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn x_value(self) -> f32 {
        return self.x;
    }

    fn keep_when_x_nonzero(self) -> Vec3 {
        let len: f32 = self.x_value();
        if (len == 0.0) {
            return self;
        }
        return self;
    }
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 4.0, y: 1.0, z: 2.0 };
    let result: Vec3 = value.keep_when_x_nonzero();
    if (result.x > 3.5) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("aggregate-return method with f32 receiver-call local should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate-return method f32 receiver call local",
        "aggregate_return_method_f32_receiver_call_local",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_nested_f32_return_call_with_aggregate_receiver_arg() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/f32.lani"),
        r#"
module app::main;

import core::f32;

struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }

    fn length(self) -> f32 {
        return core::f32::sqrt(self.dot(self));
    }
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 2.0, y: 0.0, z: 0.0 };
    let result: f32 = value.length();
    if (result > 1.9 && result < 2.1) {
        return 0;
    }
    return 1;
}
"#,
    ])
    .expect("nested f32 return call with aggregate receiver arg should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM nested f32 return call with aggregate receiver arg",
        "nested_f32_return_call_aggregate_receiver_arg",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_aggregate_return_method_with_f32_expr_arg() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        return Vec3 { x: x, y: y, z: z };
    }

    fn mul_scalar(self, scale: f32) -> Vec3 {
        return Vec3::new(self.x * scale, self.y * scale, self.z * scale);
    }

    fn scaled(self) -> Vec3 {
        let len: f32 = self.x;
        if (len == 0.0) {
            return self;
        }
        return self.mul_scalar(1.0 / len);
    }
}

fn main() -> i32 {
    let value: Vec3 = Vec3 { x: 2.0, y: 0.0, z: 0.0 };
    let result: Vec3 = value.scaled();
    if (result.x > 0.9 && result.x < 1.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("aggregate return method with f32 expression arg should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate return method with f32 expression arg",
        "aggregate_return_method_f32_expr_arg",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_f32_sqrt_like_loop_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn sqrt_like(value: f32) -> f32 {
    if (value <= 0.0) {
        return 0.0;
    }

    let guess: f32 = value;
    if (guess < 1.0) {
        guess = 1.0;
    }

    let iteration: i32 = 0;
    while (iteration < 4) {
        guess = 0.5 * (guess + value / guess);
        iteration = iteration + 1;
    }
    return guess;
}

fn main() -> i32 {
    let result: f32 = sqrt_like(4.0);
    if (result > 1.9 && result < 2.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("sqrt-like f32 loop should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM sqrt-like f32 loop",
        "sqrt_like_f32_loop",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_imported_core_f32_sqrt_with_node() {
    common::require_node();
    let wasm = common::compile_source_pack_to_wasm_with_timeout(&[
        include_str!("../stdlib/core/f32.lani"),
        r#"
module app::main;

import core::f32;

fn main() -> i32 {
    let result: f32 = core::f32::sqrt(4.0);
    if (result > 1.9 && result < 2.1) {
        return 0;
    }
    return 1;
}
"#,
    ])
    .expect("imported core::f32 sqrt should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM imported core f32 sqrt",
        "imported_core_f32_sqrt",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_aggregate_return_local_member_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

fn make_vec(x: f32, y: f32, z: f32) -> Vec3 {
    let result: Vec3 = Vec3 { x: x, y: y, z: z };
    return result;
}

fn main() -> i32 {
    let value: Vec3 = make_vec(1.0, 2.0, 3.0);
    let y: f32 = value.y;
    if (y > 1.9 && y < 2.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("aggregate returns should compile to pointer-valued WASM ABI");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate return local member",
        "aggregate_return_local_member",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_aggregate_return_direct_call_with_member_expr_args() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn new(x: f32, y: f32, z: f32) -> Vec3 {
        let result: Vec3 = Vec3 { x: x, y: y, z: z };
        return result;
    }

    fn add(self, right: Vec3) -> Vec3 {
        return Vec3::new(self.x + right.x, self.y + right.y, self.z + right.z);
    }
}

fn main() -> i32 {
    let left: Vec3 = Vec3::new(1.0, 2.0, 3.0);
    let right: Vec3 = Vec3::new(4.0, 5.0, 6.0);
    let sum: Vec3 = left.add(right);
    if (sum.y > 6.9 && sum.y < 7.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("aggregate-return direct calls should accept scalar expression arguments");

    let status = common::run_wasm_main_return_with_node(
        "WASM aggregate return direct call with member expr args",
        "aggregate_return_direct_call_member_expr_args",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_let_binary_expr_with_direct_call_operand() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
struct Vec3 {
    x: f32,
    y: f32,
    z: f32,
}

impl Vec3 {
    fn dot(self, right: Vec3) -> f32 {
        return self.x * right.x + self.y * right.y + self.z * right.z;
    }
}

fn main() -> i32 {
    let left: Vec3 = Vec3 { x: 3.0, y: 0.0, z: 0.0 };
    let right: Vec3 = Vec3 { x: 2.0, y: 0.0, z: 0.0 };
    let c: f32 = left.dot(right) - right.x * right.x;
    if (c > 1.9 && c < 2.1) {
        return 0;
    }
    return 1;
}
"#,
    )
    .expect("let binary expression with direct-call operand should compile to WASM");

    let status = common::run_wasm_main_return_with_node(
        "WASM let binary direct-call operand",
        "let_binary_direct_call_operand",
        &wasm,
    );
    assert_eq!(status, 0);
}

#[test]
fn wasm_executes_array_literal_indexed_accumulation() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let values: [i32; 5] = [3, 1, 4, 1, 5];
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 5) {
        total += values[i];
        i += 1;
    }
    print(total);
    return 0;
}
"#,
    )
    .expect("array literal indexed accumulation should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM array literal indexed accumulation",
        "array_index_accum",
        &wasm,
    );
    assert_eq!(stdout, "14\n");
}

#[test]
fn wasm_executes_scalar_while_loop_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let i: i32 = 1;
    let total: i32 = 0;
    while (i <= 10) {
        total += i;
        i += 1;
    }
    print(total);
    return 0;
}
"#,
    )
    .expect("scalar while construct should compile to WASM");

    let stdout = common::run_wasm_main_with_node("WASM scalar while construct", "while_sum", &wasm);
    assert_eq!(stdout, "55\n");
}

#[test]
fn wasm_executes_nested_boolean_conditions_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let total: i32 = 0;
    let t_min: i32 = 2;
    let t_max: i32 = 4;
    let root: i32 = 5;
    if (root < t_min || root > t_max) {
        total += 10;
    } else {
        total += 100;
    }

    let root_ok: i32 = 3;
    if (root_ok < t_min || root_ok > t_max) {
        total += 1000;
    } else {
        total += 1;
    }

    let threshold: i32 = 0;
    let scaled: i32 = 5;
    let byte: i32 = 250;
    while (threshold <= scaled && byte < 255) {
        threshold += 2;
        byte += 1;
        total += 1;
    }

    print(total);
    return 0;
}
"#,
    )
    .expect("nested boolean conditions should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM nested boolean conditions",
        "nested_boolean_conditions",
        &wasm,
    );
    assert_eq!(stdout, "14\n");
}

#[test]
fn wasm_executes_runtime_if_else_after_assignment_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let x: i32 = 0;
    x += 1;
    if (x == 1) {
        print(7);
    } else {
        print(9);
    }
    return 0;
}
"#,
    )
    .expect("runtime if/else should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM runtime if/else after assignment",
        "runtime_if_else",
        &wasm,
    );
    assert_eq!(stdout, "7\n");
}

#[test]
fn wasm_executes_while_break_and_continue_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let i: i32 = 0;
    let total: i32 = 0;
    while (i < 8) {
        i += 1;
        if (i == 3) {
            continue;
        }
        if (i > 5) {
            break;
        }
        total += i;
    }
    print(total);
    return 0;
}
"#,
    )
    .expect("while break/continue should compile to WASM");

    let stdout =
        common::run_wasm_main_with_node("WASM while break/continue", "while_break_continue", &wasm);
    assert_eq!(stdout, "12\n");
}

#[test]
fn wasm_executes_numeric_range_for_loop_with_break_continue_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let end: i32 = 8;
    let total: i32 = 0;
    for value in 2..end {
        if (value == 4) {
            continue;
        }
        if (value == 7) {
            break;
        }
        total += value;
    }
    print(total);
    return 0;
}
"#,
    )
    .expect("numeric range for construct should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM numeric range for construct",
        "numeric_range_for",
        &wasm,
    );
    assert_eq!(stdout, "16\n");
}

#[test]
fn wasm_executes_direct_user_function_call_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn add_fee(value: i32) -> i32 {
    return value + 4;
}

fn main() {
    print(add_fee(36));
    return 0;
}
"#,
    )
    .expect("direct scalar function call should compile to WASM");

    let stdout = common::run_wasm_main_with_node("WASM direct function call", "direct_call", &wasm);
    assert_eq!(stdout, "40\n");
}

#[test]
fn wasm_executes_direct_user_function_call_with_unary_constant_expression_args() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn mix(left: i32, right: i32) -> i32 {
    return left + right;
}

fn main() {
    print(mix(-17, 23));
    return 0;
}
"#,
    )
    .expect("direct scalar function calls should accept unary constant expression arguments");

    let stdout = common::run_wasm_main_with_node(
        "WASM direct call constant expression args",
        "direct_call_const_expr_args",
        &wasm,
    );
    assert_eq!(stdout, "6\n");
}

#[test]
fn wasm_executes_direct_user_function_call_with_more_than_four_args() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn sum5(a: i32, b: i32, c: i32, d: i32, e: i32) -> i32 {
    return e;
}

fn main() {
    print(sum5(1, 2, 3, 4, 5));
    return 0;
}
"#,
    )
    .expect("direct scalar function calls should not be capped at four arguments");

    let stdout = common::run_wasm_main_with_node(
        "WASM direct call more than four args",
        "direct_call_more_than_four_args",
        &wasm,
    );
    assert_eq!(stdout, "5\n");
}

#[test]
fn wasm_executes_mixed_scalar_direct_user_function_call_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn choose(flag: i32, value: f32) -> i32 {
    if (value > 2.0) {
        return flag;
    }
    return 0;
}

fn main() {
    print(choose(37, 2.5));
    return 0;
}
"#,
    )
    .expect("mixed scalar direct function call should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM mixed scalar direct function call",
        "mixed_scalar_direct_call",
        &wasm,
    );
    assert_eq!(stdout, "37\n");
}

#[test]
fn wasm_executes_nested_direct_user_function_calls_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn add(x: i32, y: i32) -> i32 {
    return x + y;
}

fn double(x: i32) -> i32 {
    return add(x, x);
}

fn main() {
    print(double(21));
    return 0;
}
"#,
    )
    .expect("nested direct scalar function calls should compile to WASM");

    let stdout =
        common::run_wasm_main_with_node("WASM nested function calls", "nested_direct_calls", &wasm);
    assert_eq!(stdout, "42\n");
}

#[test]
fn wasm_executes_recursive_direct_call_with_expression_argument() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn fact(n: i32) -> i32 {
    if (n <= 1) {
        return 1;
    } else {
        return n * fact(n - 1);
    }
}

fn main() {
    print(fact(6));
    return 0;
}
"#,
    )
    .expect("recursive direct call with expression argument should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM recursive direct call expression argument",
        "recursive_direct_call_expr_arg",
        &wasm,
    );
    assert_eq!(stdout, "720\n");
}

#[test]
fn wasm_executes_binary_return_with_direct_call_operand() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn bump(value: i32) -> i32 {
    return value + 1;
}

fn call_on_left(value: i32) -> i32 {
    return bump(value) + 4;
}

fn call_on_right(value: i32) -> i32 {
    return 4 + bump(value);
}

fn main() {
    print(call_on_left(37));
    print(call_on_right(37));
    return 0;
}
"#,
    )
    .expect("binary return expression with direct-call operand should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM binary return direct-call operand",
        "binary_return_direct_call_operand",
        &wasm,
    );
    assert_eq!(stdout, "42\n42\n");
}

#[test]
fn wasm_executes_multiple_explicit_returns_with_node() {
    common::require_node();
    let wasm = common::compile_source_to_wasm_with_timeout(
        r#"
fn abs_i32(value: i32) -> i32 {
    if (value < 0) {
        return -value;
    } else {
        return value;
    }
}

fn main() {
    let negative: i32 = -17;
    let checked: i32 = abs_i32(negative);
    if (checked == 17) {
        let positive: i32 = abs_i32(23);
        print(positive);
        return 0;
    } else {
        return 1;
    }
}
"#,
    )
    .expect("multiple explicit returns should compile to WASM");

    let stdout = common::run_wasm_main_with_node(
        "WASM multiple explicit returns",
        "multiple_returns",
        &wasm,
    );
    assert_eq!(stdout, "23\n");
}

#[test]
fn wasm_rejects_for_construct_with_stable_backend_diagnostic() {
    let err = common::compile_source_to_wasm_with_timeout(
        r#"
fn main() {
    let values: [i32; 3] = [1, 2, 3];
    let total: i32 = 0;
    for value in values {
        total += value;
    }
    return total;
}
"#,
    )
    .expect_err("WASM should fail closed for loops until WASM lowering consumes for records");

    assert_wasm_backend_boundary(err);
}

fn assert_wasm_backend_boundary(err: CompileError) {
    match err {
        CompileError::Diagnostic(diagnostic) => {
            let message = diagnostic.render();
            assert_eq!(
                diagnostic.code, "LNC0036",
                "WASM backend rejection should use a stable diagnostic: {message}"
            );
            assert!(
                diagnostic.message.contains("WASM") || diagnostic.message.contains("unsupported"),
                "diagnostic should identify the WASM backend boundary: {message}"
            );
            let label = diagnostic
                .primary_label
                .as_ref()
                .expect("WASM backend diagnostic should include a primary label");
            assert!(
                label.line > 0,
                "diagnostic should be source-spanned: {message}"
            );
            assert!(
                label.column > 0,
                "diagnostic should include a source column: {message}"
            );
            assert!(
                label.length > 0,
                "diagnostic span should be non-empty: {message}"
            );
        }
        other => panic!("expected stable WASM backend diagnostic, got {other:?}"),
    }
}
