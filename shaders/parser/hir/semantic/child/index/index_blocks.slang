// The second level of the child-index heaps (index_tree.slang): one local
// (minimum, count) heap over each group of 256 block aggregates from
// index_rows. One workgroup owns one group.

import blocked_search_tree;
import parser.hir.semantic.parent.end_tree;
import parser.hir.semantic.child.index.index_tree;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint2> hir_semantic_child_local;

RWStructuredBuffer<uint2> hir_semantic_child_blocks;

static const uint MAX_GROUPS_X = 65535u;

groupshared uint2 s_heap[512];

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
        (active_semantic_count() + CHILD_INDEX_FANOUT - 1u) / CHILD_INDEX_FANOUT;
    // The whole group leaves together; index_top reads its aggregate as the
    // identity.
    if (group >= semantic_end_group_count(gHirSemantic.n) ||
        group * CHILD_INDEX_FANOUT >= active_blocks)
        return;
    uint block = group * CHILD_INDEX_FANOUT + lane;
    uint2 aggregate = block < active_blocks
        ? hir_semantic_child_local[block * CHILD_INDEX_FANOUT]
        : ChildIndexMinCount.identity();
    blocked_local_heap_build<uint2, ChildIndexMinCount>(lane, aggregate, s_heap);
    hir_semantic_child_blocks[group * CHILD_INDEX_FANOUT + lane] = s_heap[max(lane, 1u)];
}
