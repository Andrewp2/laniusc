// The top level of the canonical-end search heaps (end_rows.slang): the heap
// over the group maxima from end_blocks, built level by level by one
// workgroup. Device-memory barriers separate the levels.

import parser.hir.semantic.parent.end_tree;

struct Params
{
    uint raw_capacity;
    uint canonical_capacity;
    uint uses_status_count;
    uint local_ancestor_span;
    uint records_use_token_rows;
};

ConstantBuffer<Params> gCanonical;

StructuredBuffer<uint> canonical_count;
StructuredBuffer<uint> hir_canonical_end_blocks;

RWStructuredBuffer<uint> hir_canonical_end_top;

static const uint WG_SIZE = 256u;

// Top heap node 1 <= node < 2 * groups: a group's maximum from node `groups`
// on.
uint top_node(uint node, uint groups, uint active_groups)
{
    if (node < groups)
        return hir_canonical_end_top[node];
    uint group = node - groups;
    return group < active_groups ? hir_canonical_end_blocks[group * SEMANTIC_END_FANOUT] : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint groups = semantic_end_group_count(gCanonical.canonical_capacity);
    uint group_rows = SEMANTIC_END_FANOUT * SEMANTIC_END_FANOUT;
    uint count = min(canonical_count[0u], gCanonical.canonical_capacity);
    uint active_groups = (count + group_rows - 1u) / group_rows;
    for (uint width = groups >> 1u; width > 0u; width >>= 1u)
    {
        for (uint i = lane; i < width; i += WG_SIZE)
        {
            uint node = width + i;
            hir_canonical_end_top[node] = max(
                top_node(node * 2u, groups, active_groups),
                top_node(node * 2u + 1u, groups, active_groups));
        }
        DeviceMemoryBarrierWithGroupSync();
    }
}
