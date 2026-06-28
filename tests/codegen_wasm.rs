mod common;

use laniusc_compiler::compiler::CompileError;

#[test]
fn wasm_hir_body_uses_fragment_count_scan_scatter_pipeline() {
    let collect = include_str!("../shaders/codegen/wasm/hir/body_plan_collect.slang");
    let validate = include_str!("../shaders/codegen/wasm/hir/body_plan_validate.slang");
    let plan = include_str!("../shaders/codegen/wasm/hir/body_plan.slang");
    let common = include_str!("../shaders/codegen/wasm/hir/body_common.slang");
    let let_init_clear = include_str!("../shaders/codegen/wasm/hir/body_let_init_clear.slang");
    let let_init = include_str!("../shaders/codegen/wasm/hir/body_let_init.slang");
    let clear = include_str!("../shaders/codegen/wasm/hir/body_clear.slang");
    let counts = include_str!("../shaders/codegen/wasm/hir/body.slang");
    let scan_local = include_str!("../shaders/codegen/wasm/hir/body_scan_local.slang");
    let scan_blocks = include_str!("../shaders/codegen/wasm/hir/body_scan_blocks.slang");
    let body_status = include_str!("../shaders/codegen/wasm/hir/body_status.slang");
    let scatter = include_str!("../shaders/codegen/wasm/hir/body_scatter.slang");
    let agg_body = include_str!("../shaders/codegen/wasm/hir/agg_body.slang");
    let assert_module = include_str!("../shaders/codegen/wasm/hir/assert_module.slang");
    let module_status = include_str!("../shaders/codegen/wasm/module_status.slang");
    let module = include_str!("../shaders/codegen/wasm/module.slang");
    let backend = include_str!("../crates/laniusc-compiler/src/codegen/wasm.rs");

    assert!(
        collect.contains("atomic_u32_add(body_plan, BODY_PLAN_MAIN_COUNT")
            && validate.contains("atomic_u32_add(body_plan, BODY_PLAN_RETURN_COUNT")
            && plan.contains("plan_aggregate_ok(")
            && plan.contains("BODY_PLAN_FINALIZE_SLOT_COUNT")
            && plan.contains("GroupMemoryBarrierWithGroupSync();")
            && plan.contains("final_body_plan_word(")
            && !plan.contains("linear_dispatch_id(tid) != 0u"),
        "WASM body planning should collect and validate HIR facts in parallel, then publish final aggregate slots by lane"
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
            && counts.contains("body_fragment_for_node("),
        "WASM body fragments should be produced by HIR-node lanes, not token lanes searching HIR"
    );
    assert!(
        let_init_clear.contains("body_let_init_expr_by_decl_token[token_i] = INVALID;")
            && let_init.contains("body_let_init_expr_by_decl_token[decl_token] = init_expr;")
            && common.contains("body_let_init_expr_by_decl_token[decl_token]")
            && !common.contains("for (uint node = 0u; node < active_count; node += 1u)"),
        "WASM const evaluation should resolve let initializers through a parallel decl-token table"
    );
    assert!(
        validate.contains("STMT_RECORD_KIND_IF")
            && validate.contains("if_condition_value(node, condition)")
            && validate.contains("node_enabled_by_constant_if_chain(node)")
            && common.contains("constant_if_selects_node(")
            && common.contains("hir_nearest_enclosing_control_node")
            && common.contains("node_span_contains(then_block, node)")
            && common.contains("node_span_contains(else_block, node)"),
        "WASM body validation and emission should support constant-condition if statements from HIR records"
    );
    assert!(
        clear.contains("body_fragment_len[token_i] = 0u;")
            && counts.contains("StructuredBuffer<uint> body_plan;")
            && counts.contains("body_plan[BODY_PLAN_STATUS]"),
        "WASM body counts should consume the body plan after a parallel token clear"
    );
    assert!(
        counts.contains("body_fragment_len[token_i] = fragment_len;"),
        "WASM body counts should publish token-indexed fragment byte counts"
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
            && scatter.contains("BODY_FRAGMENT_MAX_BYTES")
            && scatter.contains("body_words[offset + byte_i] = fragment_byte(meta, byte_i);")
            && !scatter.contains("for (uint byte_i = 0u; byte_i < len; byte_i += 1u)")
            && !scatter.contains("accept_body_status(")
            && !scatter.contains("reject_capacity("),
        "WASM body scatter should place fragment bytes with per-byte-slot lanes"
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
            && backend.contains("record.dispatch.hir_body_let_init_clear.start")
            && backend.contains("record.dispatch.hir_body_let_init.start")
            && backend.contains("record.dispatch.hir_body_plan_validate.start")
            && backend.contains("record.dispatch.hir_body_plan_finalize.start")
            && backend.contains("record.dispatch.hir_body_clear.start")
            && backend.contains("record.dispatch.hir_body_counts.start")
            && backend.contains("record.dispatch.hir_body_scan_local.start")
            && backend.contains("record.dispatch.hir_body_scan_blocks")
            && backend.contains("record.dispatch.hir_body_status.start")
            && backend.contains("record.dispatch.hir_body_scatter.start")
            && backend.contains("record.dispatch.module_status.start")
            && backend.contains("WASM_BODY_PLAN_FINALIZE_GROUPS")
            && backend.contains("WASM_BODY_STATUS_GROUPS")
            && backend.contains("WASM_MODULE_STATUS_GROUPS")
            && !backend.contains("dispatch_workgroups(1, 1, 1)"),
        "WASM backend should record body emission as let-init table -> plan collect -> validate -> finalize -> clear -> counts -> scan -> scatter"
    );

    let let_init_clear_pos = backend
        .find("record.dispatch.hir_body_let_init_clear.start")
        .expect("body let-init clear dispatch should be recorded");
    let let_init_pos = backend
        .find("record.dispatch.hir_body_let_init.start")
        .expect("body let-init dispatch should be recorded");
    let collect_pos = backend
        .find("record.dispatch.hir_body_plan_collect.start")
        .expect("body-plan collect dispatch should be recorded");
    let validate_pos = backend
        .find("record.dispatch.hir_body_plan_validate.start")
        .expect("body-plan validate dispatch should be recorded");
    let finalize_pos = backend
        .find("record.dispatch.hir_body_plan_finalize.start")
        .expect("body-plan finalize dispatch should be recorded");
    let counts_pos = backend
        .find("record.dispatch.hir_body_counts.start")
        .expect("body-counts dispatch should be recorded");
    let clear_pos = backend
        .find("record.dispatch.hir_body_clear.start")
        .expect("body-clear dispatch should be recorded");
    let body_status_pos = backend
        .find("record.dispatch.hir_body_status.start")
        .expect("body-status dispatch should be recorded");
    let scatter_pos = backend
        .find("record.dispatch.hir_body_scatter.start")
        .expect("body-scatter dispatch should be recorded");
    let enum_match_pos = backend
        .find("record.dispatch.hir_enum_match_records.start")
        .expect("enum-match dispatch should be recorded");
    let module_status_pos = backend
        .find("record.dispatch.module_status.start")
        .expect("module-status dispatch should be recorded");
    let module_pos = backend
        .find("record.dispatch.module.start")
        .expect("module dispatch should be recorded");
    assert!(
        let_init_clear_pos < let_init_pos
            && let_init_pos < collect_pos
            && collect_pos < validate_pos
            && validate_pos < finalize_pos
            && finalize_pos < clear_pos
            && clear_pos < counts_pos
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
fn wasm_rejects_for_loop_with_stable_backend_diagnostic() {
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
                diagnostic.message.contains("for loop")
                    || diagnostic.message.contains("WASM")
                    || diagnostic.message.contains("unsupported"),
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
