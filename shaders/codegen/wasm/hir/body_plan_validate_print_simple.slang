// Plan statement-position scalar print calls from dense compact HIR.
// Direct-call arguments retain their dedicated scanned-argument planner until
// that whole ABI family moves; every other argument is owned by the compact
// expression forest and never translated back to a raw parser row.

import atomics;
import gpu_index;
import compact_expr_common;
import compact_expr_byte_common;

StructuredBuffer<uint> status;
RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;

static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint INTRINSIC_TEXT_WRITE = 1u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_PRINT_COUNT_AGG = 17u;
static const uint BODY_PLAN_PRINT_MAX_TOKEN = 19u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_EXPR_CONTROL = 1u << 0u;
static const uint BODY_FRAGMENT_PRINT_EXPR_COMPACT_I64 = 76u;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool compact_print_call(uint call)
{
    if (!valid_node(call) || compact_hir_core[call].kind != HIR_CALL_EXPR ||
        (compact_hir_payload[call].d & HIR_CALL_CONTEXT_STMT_BIT) == 0u ||
        compact_hir_payload[call].c != 1u)
        return false;
    uint callee = call_callee_token(call);
    return valid_token(callee) && call_intrinsic_tag[callee] == INTRINSIC_TEXT_WRITE;
}

void publish_compact_print_invalid(uint owner_fn, uint detail)
{
    atomic_u32_add(wasm_func_invalid_count_by_token, owner_fn, 1u);
    atomic_u32_min(wasm_func_detail_by_token, owner_fn, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE) return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] > 1u) return;

    uint call = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (!compact_print_call(call)) return;

    uint owner_fn = node_enclosing_fn_token(call);
    uint token = compact_hir_core[call].token_start;
    if (!supported_function_token(owner_fn) || !valid_token(token)) return;

    uint arg = compact_call_arg_node(call, 0u);
    // The scanned direct-call artifact still owns this ABI shape. Keeping one
    // producer per fragment avoids double publication during migration.
    if (valid_node(arg) && compact_hir_core[arg].kind == HIR_CALL_EXPR) return;
    uint expr_len = compact_expr_tree_len(arg);
    if (expr_len == 0u)
    {
        publish_compact_print_invalid(owner_fn, token);
        return;
    }

    uint slot = token * 2u;
    if (body_fragment_len[slot] != 0u) return;
    uint len = expr_len + 3u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = uint4(
        BODY_FRAGMENT_PRINT_EXPR_COMPACT_I64,
        arg,
        len,
        token);
    body_fragment_aux[slot] = uint4(INVALID, 0u, 0u, 0u);
    atomic_u32_add(body_plan, BODY_PLAN_PRINT_COUNT_AGG, 1u);
    atomic_u32_max(body_plan, BODY_PLAN_PRINT_MAX_TOKEN, token);
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_EXPR_CONTROL);
    atomic_u32_add(wasm_func_body_len_by_token, owner_fn, len);
}
