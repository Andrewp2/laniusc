// Plan scalar assignments whose target and RHS are represented entirely by
// dense compact-HIR identities.

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
static const uint HIR_STMT = 7u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_FEATURE_MASK = 35u;
static const uint BODY_FEATURE_EXPR_CONTROL = 1u << 0u;
static const uint BODY_FRAGMENT_ASSIGN_EXPR_COMPACT_I32 = 65u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_COMPACT_I32 = 66u;
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
    if (core.kind != HIR_STMT || statement.a != STMT_RECORD_KIND_ASSIGN) return;

    uint owner_fn = node_enclosing_fn_token(node);
    uint token = core.token_start;
    uint target = statement.b;
    uint rhs = statement.c;
    uint op = statement.d;
    if (!supported_function_token(owner_fn) || !valid_token(token) ||
        !valid_node(target) || !valid_node(rhs))
        return;
    uint slot = token * 2u;
    if (body_fragment_len[slot] != 0u) return;

    uint local_index = INVALID;
    if (!local_decl_token_for_name_expr(target, local_index)) return;
    bool compound = op != ASSIGN_OP_SET;
    uint target_name = compact_hir_payload[target].d;
    uint target_decl = valid_token(target_name) ? visible_decl[target_name] : INVALID;
    uint value_ty = valid_token(target_decl) ? local_decl_type(target_decl) : TY_UNKNOWN;
    if (!compact_assign_op_supported(op, value_ty)) return;
    uint expr_len = compact_expr_tree_len(rhs);
    if (expr_len == 0u) return;
    uint len = expr_len + local_set_len(local_index);
    if (compound) len += local_get_len(local_index) + 1u;
    body_fragment_len[slot] = len;
    body_fragment_meta[slot] = uint4(
        compound
            ? BODY_FRAGMENT_ASSIGN_COMPOUND_EXPR_COMPACT_I32
            : BODY_FRAGMENT_ASSIGN_EXPR_COMPACT_I32,
        local_index,
        rhs,
        op | (value_ty << 8u));
    body_fragment_aux[slot] = uint4(INVALID, 0u, INVALID, value_ty);
    atomic_u32_or(body_plan, BODY_PLAN_FEATURE_MASK, BODY_FEATURE_EXPR_CONTROL);
    atomic_u32_add(wasm_func_body_len_by_token, owner_fn, len);
}
