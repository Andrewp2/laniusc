// Publish token-indexed let-initializer records and per-function local bounds
// from HIR statement rows. Expression contribution metadata consumes the
// completed local bounds, so both facts are owned by this prepass.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> enclosing_fn;

RWStructuredBuffer<uint> body_let_init_expr_by_decl_token;
RWStructuredBuffer<uint> wasm_func_local_max_by_token;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_STMT = 7u;
static const uint HIR_EXPR = 14u;
static const uint HIR_FOR_STMT = 30u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_FOR = 6u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint stmt_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

void publish_function_local(uint decl_token)
{
    if (!valid_token(decl_token))
        return;
    uint encoded_fn = enclosing_fn[decl_token];
    uint owner_fn = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    if (!valid_token(owner_fn))
        return;
    uint prior = atomic_u32_compare_exchange(
        wasm_func_local_max_by_token,
        owner_fn,
        INVALID,
        decl_token);
    if (prior != INVALID)
        atomic_u32_max(wasm_func_local_max_by_token, owner_fn, decl_token);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint stmt_kind = stmt_record_slot(node, 0u);
    bool is_let = hir_kind[node] == HIR_LET_STMT && stmt_kind == STMT_RECORD_KIND_LET;
    bool is_for =
        (hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT) &&
        stmt_kind == STMT_RECORD_KIND_FOR;
    if (!is_let && !is_for)
        return;
    uint decl_token = stmt_record_slot(node, 1u);
    publish_function_local(decl_token);
    if (!is_let)
    {
        uint iterable = stmt_record_slot(node, 2u);
        uint resolved = valid_node(iterable) ? hir_expr_result_root_node[iterable] : INVALID;
        if (valid_node(resolved))
            iterable = resolved;
        publish_function_local(valid_node(iterable) ? hir_token_end[iterable] : INVALID);
        return;
    }

    uint init_expr = stmt_record_slot(node, 2u);
    if (valid_token(decl_token) &&
        valid_node(init_expr) &&
        hir_kind[init_expr] == HIR_EXPR)
    {
        body_let_init_expr_by_decl_token[decl_token] = init_expr;
    }
}
