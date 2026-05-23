// x86_64 nearest enclosing HIR statement seed.
//
// This pass seeds a parent-link relation so statement-level call projections
// can consume an enclosing-statement record instead of walking parent chains in
// the projection shader.

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
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> x86_tree_subtree_end;

RWStructuredBuffer<uint> x86_enclosing_stmt_node;
RWStructuredBuffer<uint> x86_enclosing_stmt_link;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint HIR_STMT = 7u;

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

bool is_stmt_node(uint node)
{
    return valid_node(node) && hir_kind[node] == HIR_STMT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint parent = x86_tree_parent[node];
    if (is_stmt_node(parent))
    {
        x86_enclosing_stmt_node[node] = parent;
        x86_enclosing_stmt_link[node] = INVALID;
        return;
    }

    x86_enclosing_stmt_node[node] = INVALID;
    x86_enclosing_stmt_link[node] = valid_node(parent) ? parent : INVALID;
}
