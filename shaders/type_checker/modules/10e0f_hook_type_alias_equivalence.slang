// One parallel connectivity-hooking round over the static alias substitution
// edges. Replaying this with pointer-jumping contracts every component without
// a chain-depth or generic-arity loop in any lane.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> alias_equiv_edge_0;
StructuredBuffer<uint> alias_equiv_edge_1;
RWStructuredBuffer<uint> alias_equiv_parent;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint graph_capacity()
{
    return gParams.n_tokens > INVALID - gParams.n_hir_nodes
        ? INVALID
        : gParams.n_tokens + gParams.n_hir_nodes;
}

void hook(uint left, uint right)
{
    uint capacity = graph_capacity();
    if (left >= capacity || right >= capacity)
        return;
    uint left_parent = alias_equiv_parent[left];
    uint right_parent = alias_equiv_parent[right];
    if (left_parent >= capacity || right_parent >= capacity || left_parent == right_parent)
        return;
    uint high = max(left_parent, right_parent);
    uint low = min(left_parent, right_parent);
    atomic_u32_min(alias_equiv_parent, high, low);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (node >= gParams.n_hir_nodes)
        return;
    uint graph_node = gParams.n_tokens + node;
    hook(graph_node, alias_equiv_edge_0[node]);
    hook(graph_node, alias_equiv_edge_1[node]);
}
