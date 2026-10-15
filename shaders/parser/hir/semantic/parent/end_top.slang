// The top level of the semantic-end search heaps (end_tree.slang): the heap
// over the group maxima from end_blocks, built level by level by one
// workgroup. Device-memory barriers separate the levels.

import parser.hir.semantic.parent.end_tree;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_end_blocks;

RWStructuredBuffer<uint> hir_semantic_end_top;

static const uint WG_SIZE = 256u;

uint active_semantic_count()
{
    uint active_nodes = gHirSemantic.uses_status_count != 0u
        ? min(gHirSemantic.n, tree_count_status[5u])
        : gHirSemantic.n;
    return min(hir_semantic_count[0u], active_nodes);
}

// Top heap node 1 <= node < 2 * groups: a group's maximum from node `groups`
// on.
uint top_node(uint node, uint groups, uint active_groups)
{
    if (node < groups)
        return hir_semantic_end_top[node];
    uint group = node - groups;
    return group < active_groups ? hir_semantic_end_blocks[group * SEMANTIC_END_FANOUT] : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint groups = semantic_end_group_count(gHirSemantic.n);
    uint block_rows = SEMANTIC_END_FANOUT * SEMANTIC_END_FANOUT;
    uint active_groups = (active_semantic_count() + block_rows - 1u) / block_rows;
    for (uint width = groups >> 1u; width > 0u; width >>= 1u)
    {
        for (uint i = lane; i < width; i += WG_SIZE)
        {
            uint node = width + i;
            hir_semantic_end_top[node] = max(
                top_node(node * 2u, groups, active_groups),
                top_node(node * 2u + 1u, groups, active_groups));
        }
        DeviceMemoryBarrierWithGroupSync();
    }
}
