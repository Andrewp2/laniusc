mod common;

use laniusc_compiler::compiler::CompileError;

#[test]
fn wasm_hir_body_uses_fragment_count_scan_scatter_pipeline() {
    let functions_mark = include_str!("../shaders/codegen/wasm/hir/functions_mark.slang");
    let functions_reach = include_str!("../shaders/codegen/wasm/hir/functions_reach.slang");
    let functions_count = include_str!("../shaders/codegen/wasm/hir/functions_count.slang");
    let plan_functions = include_str!("../shaders/codegen/wasm/hir/body_plan_functions.slang");
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
        functions_mark.contains("atomic_u32_add(body_plan, BODY_PLAN_MAIN_COUNT")
            && validate.contains("atomic_u32_add(wasm_func_return_count_by_token, owner_fn, 1u)")
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
            && validate.contains("publish_fragment(")
            && counts.contains("Publish function wrapper fragments"),
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
            && validate.contains("if_open_fragment_and_len(node, condition_node, open_len)")
            && validate.contains("if_end_token_and_len(node, end_token, end_len)")
            && validate.contains("if_else_token_and_len(node, else_token, else_len)")
            && validate.contains("BODY_FRAGMENT_IF_ELSE")
            && validate.contains("BODY_FRAGMENT_IF_END")
            && scatter.contains("BODY_FRAGMENT_IF_OPEN_I32")
            && scatter.contains("WASM_IF")
            && !validate.contains("if_condition_value(node, condition)")
            && !validate.contains("node_enabled_by_constant_if_chain(node)")
            && !common.contains("constant_if_selects_node("),
        "WASM body validation and emission should lower runtime if/else control from HIR records"
    );
    assert!(
        validate.contains("STMT_RECORD_KIND_WHILE")
            && validate.contains("while_open_fragment_and_len(node, condition_node, open_len)")
            && common.contains("while_close_token_and_len(")
            && validate.contains("BODY_FRAGMENT_WHILE_CLOSE")
            && scatter.contains("BODY_FRAGMENT_WHILE_OPEN_I32")
            && scatter.contains("expr_simple_byte("),
        "WASM body validation and emission should lower simple scalar while loops from HIR records and semantic expression tables"
    );
    assert!(
        validate.contains("STMT_RECORD_KIND_BREAK")
            && validate.contains("STMT_RECORD_KIND_CONTINUE")
            && validate.contains("loop_control_fragment_and_len(node, depth, len)")
            && common.contains("hir_nearest_loop_node")
            && common.contains("loop_control_branch_depth(")
            && scatter.contains("BODY_FRAGMENT_BRANCH")
            && scatter.contains("branch_fragment_byte("),
        "WASM body validation and emission should lower break/continue from parser-owned HIR control context"
    );
    assert!(
        validate.contains("STMT_RECORD_KIND_FOR")
            && validate.contains("for_open_range_fragment_and_len(")
            && validate.contains("for_close_token_and_len(")
            && validate.contains("BODY_FRAGMENT_FOR_CLOSE_RANGE_I32")
            && counts.contains("BODY_FRAGMENT_FUNCTION_END")
            && common.contains("numeric_range_iterable_for_for_node(")
            && common.contains("BODY_FRAGMENT_FOR_OPEN_RANGE_I32")
            && common.contains("BODY_FRAGMENT_FUNCTION_END")
            && scatter.contains("for_open_range_i32_fragment_byte(")
            && scatter.contains("for_close_range_i32_fragment_byte("),
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
            && validate.contains("RWStructuredBuffer<uint4> body_fragment_aux;")
            && validate.contains("direct_call_aux(")
            && counts.contains("body_fragment_aux[slot] = uint4(INVALID, 0u, 0u, 0u);"),
        "WASM body record producers should publish fragment lengths, metadata, and auxiliary call records after a parallel token clear"
    );
    assert!(
        validate.contains("uint slot = token_i * 2u;")
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
            && scatter.contains("BODY_FRAGMENT_MAX_BYTES")
            && scatter.contains("uint4 aux = body_fragment_aux[token_i];")
            && scatter
                .contains("body_words[offset + byte_i] = fragment_byte(meta, aux, len, byte_i);")
            && scatter.contains("direct_call_expr_byte_from_record(")
            && !scatter.contains("for (uint byte_i = 0u; byte_i < len; byte_i += 1u)")
            && !scatter.contains("accept_body_status(")
            && !scatter.contains("reject_capacity("),
        "WASM body scatter should place fragment bytes with per-byte-slot lanes from fragment records"
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
