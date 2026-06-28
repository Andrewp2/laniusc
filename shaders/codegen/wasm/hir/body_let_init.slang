// Publish token-indexed let-initializer records from HIR statement rows.

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

RWStructuredBuffer<uint> body_let_init_expr_by_decl_token;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_EXPR = 14u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node) ||
        hir_kind[node] != HIR_LET_STMT ||
        stmt_record_slot(node, 0u) != STMT_RECORD_KIND_LET)
    {
        return;
    }

    uint decl_token = stmt_record_slot(node, 1u);
    uint init_expr = stmt_record_slot(node, 2u);
    if (valid_token(decl_token) &&
        valid_node(init_expr) &&
        hir_kind[init_expr] == HIR_EXPR)
    {
        body_let_init_expr_by_decl_token[decl_token] = init_expr;
    }
}
