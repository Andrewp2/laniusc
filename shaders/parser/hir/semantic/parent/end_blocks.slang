// The second level of the semantic-end search heaps (end_tree.slang): one
// local maximum heap over each group of 256 block maxima from end_rows. One
// workgroup owns one group.

import prefix_scan;
import blocked_search_tree;
import parser.hir.semantic.parent.end_tree;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_end_local_max;

RWStructuredBuffer<uint> hir_semantic_end_blocks;

static const uint MAX_GROUPS_X = 65535u;

groupshared uint s_heap[512];

uint active_semantic_count()
{
    uint active_nodes = gHirSemantic.uses_status_count != 0u
        ? min(gHirSemantic.n, tree_count_status[5u])
        : gHirSemantic.n;
    return min(hir_semantic_count[0u], active_nodes);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group = gid.x + gid.y * MAX_GROUPS_X;
    uint lane = ltid.x;
    uint active_blocks =
        (active_semantic_count() + SEMANTIC_END_FANOUT - 1u) / SEMANTIC_END_FANOUT;
    // The whole group leaves together; end_top reads its maximum as 0.
    if (group >= semantic_end_group_count(gHirSemantic.n) ||
        group * SEMANTIC_END_FANOUT >= active_blocks)
        return;
    uint block = group * SEMANTIC_END_FANOUT + lane;
    uint block_max = block < active_blocks
        ? hir_semantic_end_local_max[block * SEMANTIC_END_FANOUT]
        : 0u;
    blocked_local_heap_build<uint, PrefixScanU32Max>(lane, block_max, s_heap);
    hir_semantic_end_blocks[group * SEMANTIC_END_FANOUT + lane] = s_heap[max(lane, 1u)];
}
