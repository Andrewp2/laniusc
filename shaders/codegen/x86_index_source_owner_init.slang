// x86_64 index-source ownership seed.
//
// This pass marks the base-expression root of each index expression and seeds a
// parent-link relation. The step pass propagates the owning index expression to
// descendants, so instruction generation can classify index-base failures from
// a record instead of bounded parent walks.

import gpu_index;

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
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> x86_tree_parent;

RWStructuredBuffer<uint> x86_index_source_owner;
RWStructuredBuffer<uint> x86_index_source_link;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint HIR_EXPR = 14u;
static const uint HIR_INDEX_EXPR = 20u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_INDEX = 26u;

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

uint expr_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_FORM) : 0u;
}

bool is_index_expr_node(uint node)
{
    if (!valid_node(node))
        return false;
    if (hir_kind[node] == HIR_INDEX_EXPR)
        return true;
    return hir_kind[node] == HIR_EXPR && expr_form(node) == HIR_EXPR_INDEX;
}

uint index_base_node(uint index_node)
{
    return valid_node(index_node) ? expr_slot(index_node, EXPR_RECORD_LEFT) : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

bool is_index_base_root(uint node, uint parent)
{
    if (!is_index_expr_node(parent))
        return false;

    uint base = index_base_node(parent);
    uint resolved_base = resolve_expr(base);
    return node == base || node == resolved_base;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint parent = x86_tree_parent[node];
    if (is_index_base_root(node, parent))
    {
        x86_index_source_owner[node] = parent;
        x86_index_source_link[node] = INVALID;
        return;
    }

    x86_index_source_owner[node] = INVALID;
    x86_index_source_link[node] =
        valid_node(parent) && !is_index_expr_node(parent) ? parent : INVALID;
}
