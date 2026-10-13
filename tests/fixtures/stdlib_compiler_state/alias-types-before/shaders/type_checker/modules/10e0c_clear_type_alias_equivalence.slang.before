// Initialize the alias-substitution equivalence graph. Graph nodes are token
// positions followed by HIR nodes; two compact HIR-indexed edge tables retain
// the producer-owned substitution relation.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> alias_equiv_parent_a;
RWStructuredBuffer<uint> alias_equiv_parent_b;
RWStructuredBuffer<uint> alias_equiv_edge_0;
RWStructuredBuffer<uint> alias_equiv_edge_1;
RWStructuredBuffer<uint> alias_equiv_component_source;
RWStructuredBuffer<uint> alias_normalized_source;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint graph_capacity()
{
    return gParams.n_tokens > INVALID - gParams.n_hir_nodes
        ? INVALID
        : gParams.n_tokens + gParams.n_hir_nodes;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (i < graph_capacity())
    {
        alias_equiv_parent_a[i] = i;
        alias_equiv_parent_b[i] = i;
        alias_equiv_component_source[i] = INVALID;
    }
    if (i < gParams.n_hir_nodes)
    {
        alias_equiv_edge_0[i] = INVALID;
        alias_equiv_edge_1[i] = INVALID;
        alias_normalized_source[i] = INVALID;
    }
}
