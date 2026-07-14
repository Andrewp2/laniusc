// One race-free pointer-jumping round over alias-substitution components.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> alias_equiv_parent_in;
RWStructuredBuffer<uint> alias_equiv_parent_out;

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
    uint node = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint capacity = graph_capacity();
    if (node >= capacity)
        return;
    uint parent = alias_equiv_parent_in[node];
    alias_equiv_parent_out[node] = parent < capacity
        ? alias_equiv_parent_in[parent]
        : node;
}
