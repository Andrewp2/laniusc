// Publish dense-HIR let-initializer identities and per-function local bounds
// from compact statement rows. No raw parser node may enter this table: every
// later expression pass indexes the compact expression forest with its value.

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

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_expr_root;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> enclosing_fn;

RWStructuredBuffer<uint> body_let_init_expr_by_decl_token;
RWStructuredBuffer<uint> body_let_init_hir_by_decl_token;
RWStructuredBuffer<uint> wasm_func_local_max_by_token;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_STMT = 7u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_EXPR = 14u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_FOR = 7u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_hir(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint active_raw_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_raw_node(uint node)
{
    return node != INVALID && node < active_raw_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint raw_stmt_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

void publish_legacy_raw_initializer(uint raw)
{
    if (!valid_raw_node(raw) || hir_kind[raw] != HIR_LET_STMT ||
        raw_stmt_record_slot(raw, 0u) != STMT_RECORD_KIND_LET)
    {
        return;
    }
    uint decl_token = raw_stmt_record_slot(raw, 1u);
    uint init_expr = raw_stmt_record_slot(raw, 2u);
    if (valid_token(decl_token) && valid_raw_node(init_expr) &&
        hir_kind[init_expr] == HIR_EXPR)
    {
        body_let_init_expr_by_decl_token[decl_token] = init_expr;
    }
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
    publish_legacy_raw_initializer(node);
    if (!valid_hir(node))
        return;

    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    uint stmt_kind = payload.a;
    bool is_let = core.kind == HIR_LET_STMT && stmt_kind == STMT_RECORD_KIND_LET;
    bool is_for =
        (core.kind == HIR_FOR_STMT || core.kind == HIR_STMT) &&
        stmt_kind == STMT_RECORD_KIND_FOR;
    if (!is_let && !is_for)
        return;
    uint decl_token = payload.b;
    publish_function_local(decl_token);
    if (!is_let)
    {
        uint iterable = payload.c;
        uint root = valid_hir(iterable) ? compact_expr_root[iterable] : INVALID;
        if (valid_hir(root))
            iterable = root;
        publish_function_local(
            valid_hir(iterable) ? compact_hir_core[iterable].token_end : INVALID);
        return;
    }

    uint init_expr = payload.c;
    if (valid_token(decl_token) && valid_hir(init_expr))
        body_let_init_hir_by_decl_token[decl_token] = init_expr;
}
