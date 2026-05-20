// x86_64 return-match ownership projection.
//
// This pass materializes direct return-statement/match-expression relations
// from HIR statement records and expression-forward resolution. Later x86
// stages consume the arrays instead of rediscovering this relationship from
// token neighborhoods or helper names.

import atomics;
import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint4> x86_node_tree_record;

RWStructuredBuffer<uint> x86_return_match_node;
RWStructuredBuffer<uint> x86_match_return_node;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_STMT = 7u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_node(uint node)
{
    return valid_index_or_invalid(node, active_hir_node_count(), INVALID);
}

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

bool node_span_contains(uint ancestor, uint node)
{
    if (!valid_node(ancestor) || !valid_node(node))
        return false;
    uint end = x86_node_tree_record[ancestor].w;
    return end != INVALID && ancestor <= node && node < end;
}

bool is_return_stmt(uint node)
{
    if (!valid_node(node) || stmt_slot(node, 0u) != STMT_RECORD_KIND_RETURN)
        return false;
    uint kind = hir_kind[node];
    return kind == HIR_RETURN_STMT || kind == HIR_STMT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint return_node = linear_dispatch_id(tid);
    if (!is_return_stmt(return_node))
        return;

    uint return_expr = stmt_slot(return_node, 1u);
    uint match_node = resolve_expr(return_expr);
    if (!valid_node(match_node) ||
        hir_kind[match_node] != HIR_MATCH_EXPR ||
        !node_span_contains(return_expr, match_node))
        return;

    x86_return_match_node[return_node] = match_node;
    atomic_u32_min(x86_match_return_node, match_node, return_node);
}
