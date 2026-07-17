// Seed compact-field-row order.
//
// Scheduling contract:
// - Dispatch after HIR active counts and name ids are available.
// - Sort passes consume this order to build a table keyed by
//   (dense owner, field name id, compact field row).
// - This pass does not scan declaration subtrees or inspect source bytes.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_field_count;

RWStructuredBuffer<uint> struct_field_key_order;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_compact_field_count()
{
    return min(compact_field_count[0u], gParams.n_tokens);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i < active_compact_field_count())
        struct_field_key_order[i] = i;
}
