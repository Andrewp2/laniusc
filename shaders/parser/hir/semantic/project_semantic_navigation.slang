// Project dense semantic-HIR navigation and compute exact depth locally.
//
// The dense semantic tree is preorder. Once nearest semantic parents and
// dense subtree ends are known, child/sibling navigation is a local record
// projection:
//   - first child is row + 1 when its parent is row
//   - next sibling is subtree_end[row] when it has the same parent
//
// The same dispatch builds the first level of the child-index heaps
// (child_index_heaps.slang): one local (minimum, count) heap over each
// block of 256 dense semantic parents, one workgroup per block. That part
// reads only hir_semantic_parent, which navigation also only reads, and
// writes only hir_semantic_child_local, which navigation never binds.

import blocked_search_tree;
import parser.hir.semantic.child_index_heaps;

struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_subtree_end;
StructuredBuffer<uint> hir_semantic_parent;

RWStructuredBuffer<uint> hir_semantic_first_child;
RWStructuredBuffer<uint> hir_semantic_next_sibling;
RWStructuredBuffer<uint> hir_semantic_depth;
RWStructuredBuffer<uint2> hir_semantic_child_local;

groupshared uint2 s_heap[512];

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirSemantic.uses_status_count != 0u ? min(gHirSemantic.n, tree_count_status[5u]) : gHirSemantic.n;
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

bool valid_semantic_row(uint row, uint semantic_count)
{
    return row != INVALID && row < semantic_count;
}

// The whole group leaves together: queries never read blocks past the
// semantic rows.
void build_child_index_block(uint block, uint lane, uint semantic_count)
{
    if (block * CHILD_INDEX_FANOUT >= semantic_count)
        return;
    uint row = block * CHILD_INDEX_FANOUT + lane;
    uint2 leaf = row < semantic_count
        ? child_index_leaf(hir_semantic_parent[row])
        : ChildIndexMinCount.identity();
    blocked_local_heap_build<uint2, ChildIndexMinCount>(lane, leaf, s_heap);
    hir_semantic_child_local[block * CHILD_INDEX_FANOUT + lane] = s_heap[max(lane, 1u)];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint semantic_count = active_semantic_count();
    build_child_index_block(gid.x + gid.y * MAX_GROUPS_X, ltid.x, semantic_count);

    uint row = linear_thread_id(dtid);
    if (row >= semantic_count)
        return;

    uint child = row + 1u;
    hir_semantic_first_child[row] =
        valid_semantic_row(child, semantic_count) &&
        hir_semantic_parent[child] == row ? child : INVALID;

    uint sibling = hir_semantic_subtree_end[row];
    uint parent = hir_semantic_parent[row];
    hir_semantic_next_sibling[row] =
        valid_semantic_row(sibling, semantic_count) &&
        hir_semantic_parent[sibling] == parent ? sibling : INVALID;

    uint ancestor = parent;
    uint depth = 0u;
    while (valid_semantic_row(ancestor, semantic_count) && depth < semantic_count)
    {
        depth += 1u;
        ancestor = hir_semantic_parent[ancestor];
    }
    hir_semantic_depth[row] = depth;
}
