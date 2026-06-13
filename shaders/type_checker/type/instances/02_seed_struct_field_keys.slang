// Seed HIR-node order for the struct-field key table.
//
// Scheduling contract:
// - Dispatch after HIR active counts and name ids are available.
// - Sort passes consume this order to build a table keyed by
//   (owner struct node, field name id, field node).
// - This pass does not scan declaration subtrees or inspect source bytes.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_active_count;

RWStructuredBuffer<uint> struct_field_key_order;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_hir_node_count()
{
    return min(hir_active_count[0u], gParams.n_hir_nodes);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_hir_node_count())
        return;
    struct_field_key_order[node] = node;
}
