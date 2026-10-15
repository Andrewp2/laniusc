// The first level of the semantic-end search heaps (end_tree.slang): one
// local maximum heap over each block of 256 dense subtree ends. One workgroup
// owns one block of the semantic rows.

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
StructuredBuffer<uint> hir_semantic_subtree_end;

RWStructuredBuffer<uint> hir_semantic_end_local_max;

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
    uint block = gid.x + gid.y * MAX_GROUPS_X;
    uint lane = ltid.x;
    uint semantic_count = active_semantic_count();
    // The whole group leaves together: searches never read blocks past the
    // semantic rows, and end_blocks reads their maxima as 0.
    if (block * SEMANTIC_END_FANOUT >= semantic_count)
        return;
    uint row = block * SEMANTIC_END_FANOUT + lane;
    uint end = row < semantic_count ? hir_semantic_subtree_end[row] : 0u;
    blocked_local_heap_build<uint, PrefixScanU32Max>(lane, end, s_heap);
    hir_semantic_end_local_max[block * SEMANTIC_END_FANOUT + lane] = s_heap[max(lane, 1u)];
}
