// Dense-HIR counterpart for scalar return planning. Fragment meta.y is always
// either a Wasm local index (RETURN_LOCAL) or a dense expression root
// (RETURN_EXPR); raw parser identities are not representable in this pass.

import atomics;
import gpu_index;
import compact_expr_common;
import compact_expr_byte_common;
import expr_tree_metadata_common;

StructuredBuffer<uint> status;
RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;
RWStructuredBuffer<uint> wasm_func_return_count_by_token;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_return_token_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;

static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_STMT_INVALID_COUNT = 11u;
static const uint BODY_PLAN_RETURN_VALUE_OK_COUNT = 20u;
static const uint BODY_PLAN_RETURN_VALUE_INVALID_COUNT = 22u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_RETURN_SCALAR = 1u << 27u;
static const uint BODY_FEATURE_RETURN_EXPR = 1u << 31u;
// Migration-only fragment identities keep raw and dense node contracts from
// being consumed by the same scatter while differential dispatch is enabled.
static const uint BODY_FRAGMENT_RETURN_EXPR_COMPACT_I32 = 61u;
static const uint DISPATCH_X_STRIDE = 16776960u;

void compact_publish_return_invalid(uint fn_token, uint detail)
{
    atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_INVALID_COUNT, 1u);
    if (!valid_token(fn_token))
    {
        atomic_u32_add(body_plan, BODY_PLAN_STMT_INVALID_COUNT, 1u);
        atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
        return;
    }
    atomic_u32_add(wasm_func_invalid_count_by_token, fn_token, 1u);
    atomic_u32_min(wasm_func_detail_by_token, fn_token, detail);
}

void compact_publish_return_fragment(
    uint token,
    uint fn_token,
    uint len,
    uint4 meta,
    uint4 aux,
    uint feature_mask)
{
    uint slot = token * 2u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = meta;
    body_fragment_aux[slot] = aux;
    atomic_u32_add(body_plan, BODY_PLAN_RETURN_VALUE_OK_COUNT, 1u);
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, feature_mask);
    atomic_u32_add(wasm_func_body_len_by_token, fn_token, len);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE) return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] > 1u) return;

    uint node = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (!valid_node(node)) return;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (core.kind != HIR_RETURN_STMT || payload.a != STMT_RECORD_KIND_RETURN) return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn)) return;
    uint token = core.token_start;
    if (!valid_token(token))
    {
        compact_publish_return_invalid(owner_fn, INVALID);
        return;
    }

    atomic_u32_add(wasm_func_return_count_by_token, owner_fn, 1u);
    atomic_u32_min(wasm_func_return_token_by_token, owner_fn, token);

    uint expr = payload.b;
    if (!valid_node(expr)) return;
    uint expr_kind = compact_hir_core[expr].kind;
    if (expr_kind == HIR_STRUCT_LITERAL_EXPR) return;
    if (expr_kind == HIR_CALL_EXPR)
    {
        uint callee_token = call_callee_token(expr);
        uint fn_token = call_fn_token_for_call(expr, callee_token);
        uint return_ty = call_return_type_for_call(expr, callee_token, fn_token);
        // Aggregate returns have a distinct ABI and body artifact. Leave them
        // to the aggregate-return planner instead of publishing a scalar
        // invalid result for a tree that is intentionally absent here.
        if (return_ty >= TY_ARRAY_BASE) return;

        // Only calls represented by the compact scalar-call artifact belong
        // to this planner. Aggregate and compiler-intrinsic ABIs have distinct
        // semantic owners.
        uint wasm_func_index = INVALID;
        uint arg_count = 0u;
        if (!wasm_call_expr_record(expr, wasm_func_index, arg_count)) return;
    }

    uint2 total = expr_subtree_total[expr];
    if (total.y != 0u || total.x == 0u)
    {
        compact_publish_return_invalid(owner_fn, token);
        return;
    }
    uint len = total.x + 1u;
    compact_publish_return_fragment(
        token,
        owner_fn,
        len,
        uint4(BODY_FRAGMENT_RETURN_EXPR_COMPACT_I32, expr, len, token),
        uint4(INVALID, 0u, 0u, 0u),
        BODY_FEATURE_RETURN_SCALAR | BODY_FEATURE_RETURN_EXPR);
}
