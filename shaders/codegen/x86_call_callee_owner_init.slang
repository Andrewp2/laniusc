// x86_64 call-callee subtree ownership seed.
//
// x86_call_records marks the resolved callee root for each HIR_CALL_EXPR.
// This pass seeds a parent-link ownership relation so later instruction
// planning can suppress every syntax node that belongs to the callee
// expression without walking parent chains in the instruction-count shader.

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
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> x86_call_callee_root_call;

RWStructuredBuffer<uint> x86_call_callee_owner_call;
RWStructuredBuffer<uint> x86_call_callee_owner_link;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint HIR_MEMBER_EXPR = 21u;

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

bool is_member_receiver_child(uint parent, uint node)
{
    return valid_node(parent) &&
           hir_kind[parent] == HIR_MEMBER_EXPR &&
           x86_call_callee_root_call[parent] != 0u &&
           hir_member_receiver_node[parent] == node;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint root_owner = x86_call_callee_root_call[node];
    if (root_owner != 0u)
    {
        x86_call_callee_owner_call[node] = root_owner;
        x86_call_callee_owner_link[node] = INVALID;
        return;
    }

    uint parent = x86_tree_parent[node];
    x86_call_callee_owner_call[node] = 0u;
    x86_call_callee_owner_link[node] =
        valid_node(parent) && !is_member_receiver_child(parent, node) ? parent : INVALID;
}
