// Plan scalar let initializers entirely from dense compact-HIR identities.

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
static const uint HIR_LET_STMT = 8u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_EXPR_CONTROL = 1u << 0u;
static const uint BODY_FRAGMENT_LET_EXPR_COMPACT_I32 = 67u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE) return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] > 1u) return;

    uint node = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (!valid_node(node)) return;
    HirCore core = compact_hir_core[node];
    HirPayload statement = compact_hir_payload[node];
    if (core.kind != HIR_LET_STMT || statement.a != STMT_RECORD_KIND_LET) return;

    uint owner_fn = node_enclosing_fn_token(node);
    uint token = core.token_start;
    uint decl_token = statement.b;
    uint init = statement.c;
    if (!supported_function_token(owner_fn) || !valid_token(token) ||
        !valid_token(decl_token) || !valid_node(init))
        return;
    uint slot = token * 2u;
    if (body_fragment_len[slot] != 0u) return;
    body_fragment_len[slot + 1u] = 0u;

    uint local_ty = visible_type_for_token(decl_token);
    if (local_ty == TY_UNKNOWN) local_ty = local_decl_type(decl_token);
    if (local_ty == TY_STRING || local_ty >= TY_ARRAY_BASE) return;
    uint local_index = INVALID;
    if (!function_non_param_local_index_for_type(
            decl_token, owner_fn, local_ty, local_index))
        return;

    uint expr_len = compact_expr_tree_len(init);
    if (expr_len == 0u) return;
    uint len = expr_len + local_set_len(local_index);
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = uint4(
        BODY_FRAGMENT_LET_EXPR_COMPACT_I32,
        local_index,
        init,
        token);
    body_fragment_aux[slot] = uint4(INVALID, 0u, INVALID, local_ty);
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_EXPR_CONTROL);
    atomic_u32_add(wasm_func_body_len_by_token, owner_fn, len);
}
