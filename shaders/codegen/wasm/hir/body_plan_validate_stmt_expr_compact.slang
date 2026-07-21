// Plan value-discarding expression statements from the dense compact-HIR
// expression forest. Calls and their arguments are sized by the same
// postorder contribution scan used by value-producing expressions.

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

static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_EXPR_CONTROL = 1u << 0u;
static const uint BODY_FRAGMENT_STMT_EXPR_COMPACT = 71u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE) return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] > 1u) return;

    uint node = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_CALL_EXPR) return;
    if ((compact_hir_payload[node].d & HIR_CALL_CONTEXT_STMT_BIT) == 0u) return;

    uint owner_fn = node_enclosing_fn_token(node);
    uint token = compact_hir_core[node].token_start;
    if (!supported_function_token(owner_fn) || !valid_token(token)) return;

    uint callee_token = call_callee_token(node);
    uint fn_token = call_fn_token_for_call(node, callee_token);
    if (call_return_type_for_call(node, callee_token, fn_token) != TY_VOID ||
        !supported_call_target_token(fn_token))
        return;

    uint expr_len = compact_expr_tree_len(node);
    if (expr_len == 0u) return;
    uint slot = token * 2u;
    if (body_fragment_len[slot] != 0u) return;

    body_fragment_len[slot] = expr_len;
    body_fragment_meta[slot] = uint4(
        BODY_FRAGMENT_STMT_EXPR_COMPACT,
        node,
        expr_len,
        token);
    body_fragment_aux[slot] = uint4(INVALID, 0u, INVALID, TY_VOID);
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_EXPR_CONTROL);
    atomic_u32_add(wasm_func_body_len_by_token, owner_fn, expr_len);
}
