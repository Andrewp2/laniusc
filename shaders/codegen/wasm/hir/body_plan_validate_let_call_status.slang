// Reject scalar let-call initializers not claimed by any let-call planner.
//
// Every reference in this pass is either a dense compact-HIR row or a token.
// It intentionally does not import body_common: that module exposes the raw
// parser tree and would extend its lifetime into this post-planning check.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint artifact_flags;
};

struct HirCore
{
    uint kind;
    uint parent;
    uint token_start;
    uint token_end;
};

struct HirPayload
{
    uint a;
    uint b;
    uint c;
    uint d;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_func_flag;
StructuredBuffer<uint> wasm_func_slot_by_token;
StructuredBuffer<uint> status;
StructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;

static const uint INVALID = 0xffffffffu;
static const uint ERR_UNSUPPORTED_SOURCE_SHAPE = 1u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_ARRAY_BASE = 128u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_CALL_EXPR = 19u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint BODY_PLAN_MAIN_COUNT = 8u;
static const uint BODY_PLAN_STMT_INVALID_COUNT = 11u;
static const uint BODY_PLAN_ERROR_DETAIL_MIN = 23u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = visible_type[token];
    if (ty != INVALID && ty != TY_UNKNOWN)
        return ty;
    uint decl = visible_decl[token];
    if (!valid_token(decl))
        return TY_UNKNOWN;
    ty = visible_type[decl];
    return ty == INVALID ? TY_UNKNOWN : ty;
}

uint node_enclosing_fn_token(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token))
        return INVALID;
    uint encoded_fn = enclosing_fn[token];
    return encoded_fn == 0u ? INVALID : encoded_fn - 1u;
}

bool supported_function_token(uint fn_token)
{
    return valid_token(fn_token) &&
           wasm_func_flag[fn_token] != 0u &&
           wasm_func_slot_by_token[fn_token] != INVALID;
}

void publish_func_invalid(uint fn_token, uint detail)
{
    if (!valid_token(fn_token))
    {
        atomic_u32_add(body_plan, BODY_PLAN_STMT_INVALID_COUNT, 1u);
        atomic_u32_min(body_plan, BODY_PLAN_ERROR_DETAIL_MIN, detail);
        return;
    }
    atomic_u32_add(wasm_func_invalid_count_by_token, fn_token, 1u);
    atomic_u32_min(wasm_func_detail_by_token, fn_token, detail);
}

bool scalar_let_call_candidate(uint node)
{
    if (!valid_node(node) || compact_hir_core[node].kind != HIR_LET_STMT)
        return false;

    HirPayload statement = compact_hir_payload[node];
    if (statement.a != STMT_RECORD_KIND_LET)
        return false;

    uint decl_token = statement.b;
    if (!valid_token(decl_token))
        return true;
    if (visible_type_for_token(decl_token) >= TY_ARRAY_BASE ||
        wasm_agg_local_width_by_token[decl_token] != 0u)
    {
        return false;
    }

    uint init_expr = statement.c;
    return valid_node(init_expr) &&
           compact_hir_core[init_expr].kind == HIR_CALL_EXPR;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (status[2u] != 0u && status[2u] != ERR_UNSUPPORTED_SOURCE_SHAPE)
        return;
    if (body_plan[BODY_PLAN_MAIN_COUNT] > 1u)
        return;

    uint node = linear_dispatch_id(tid);
    if (!scalar_let_call_candidate(node))
        return;

    uint owner_fn = node_enclosing_fn_token(node);
    if (!supported_function_token(owner_fn))
        return;

    uint token = compact_hir_core[node].token_start;
    if (!valid_token(token) || body_fragment_len[token * 2u] == 0u)
        publish_func_invalid(owner_fn, valid_token(token) ? token : INVALID);
}
