// The first level of the child-index heaps (index_tree.slang): one local
// (minimum, count) heap over each block of 256 dense semantic parents. One
// workgroup owns one block of the semantic rows.

import blocked_search_tree;
import parser.hir.semantic.child.index.index_tree;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_parent;

RWStructuredBuffer<uint2> hir_semantic_child_local;

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
    uint block = gid.x + gid.y * MAX_GROUPS_X;
    uint lane = ltid.x;
    uint semantic_count = active_semantic_count();
    // The whole group leaves together: queries never read blocks past the
    // semantic rows.
    if (block * CHILD_INDEX_FANOUT >= semantic_count)
        return;
    uint row = block * CHILD_INDEX_FANOUT + lane;
    uint2 leaf = row < semantic_count
        ? child_index_leaf(hir_semantic_parent[row])
        : ChildIndexMinCount.identity();
    blocked_local_heap_build<uint2, ChildIndexMinCount>(lane, leaf, s_heap);
    hir_semantic_child_local[block * CHILD_INDEX_FANOUT + lane] = s_heap[max(lane, 1u)];
}
