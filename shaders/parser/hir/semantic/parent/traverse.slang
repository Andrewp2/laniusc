// Find each dense semantic row's nearest semantic parent: the last earlier
// row whose dense subtree end lies past the row (end_tree.slang). One lane
// owns one semantic row and searches the semantic-end heaps, reading
// O(log distance) heap nodes instead of climbing the raw parent chain, which
// runs through long statement and item spines.

import blocked_search_tree;
import parser.hir.semantic.parent.end_tree;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_subtree_end;
StructuredBuffer<uint> hir_semantic_end_local_max;
StructuredBuffer<uint> hir_semantic_end_blocks;
StructuredBuffer<uint> hir_semantic_end_top;

RWStructuredBuffer<uint> hir_semantic_parent;

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

public struct SemanticEndTree : IBlockedSearchTree<uint>
{
    public static uint row_count()
    {
        return active_semantic_count();
    }

    public static uint row_value(uint row)
    {
        return hir_semantic_subtree_end[row];
    }

    public static uint local_node(uint block, uint node)
    {
        return hir_semantic_end_local_max[block * SEMANTIC_END_FANOUT + node];
    }

    public static uint block_leaf_base()
    {
        return semantic_end_leaf_base(gHirSemantic.n);
    }

    // Node `node` of the heap over the blocks: a block's maximum from the
    // leaf base on, a node of a group's heap down to the group roots, and a
    // top heap node above them.
    public static uint block_node(uint node)
    {
        uint leaf_base = block_leaf_base();
        if (node >= leaf_base)
        {
            uint block = node - leaf_base;
            uint active_blocks =
                (row_count() + SEMANTIC_END_FANOUT - 1u) / SEMANTIC_END_FANOUT;
            return block < active_blocks
                ? hir_semantic_end_local_max[block * SEMANTIC_END_FANOUT]
                : 0u;
        }
        uint groups = leaf_base / SEMANTIC_END_FANOUT;
        if (node < groups)
            return hir_semantic_end_top[node];
        // Group heap levels below the group root: `depth` levels down.
        uint depth = uint(firstbithigh(node)) - uint(firstbithigh(groups));
        uint group = (node >> depth) - groups;
        uint local = (1u << depth) | (node & ((1u << depth) - 1u));
        return hir_semantic_end_blocks[group * SEMANTIC_END_FANOUT + local];
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_semantic_count())
        return;

    uint node = hir_semantic_dense_node[row];
    if (node == INVALID || node >= active_node_count())
    {
        hir_semantic_parent[row] = INVALID;
        return;
    }
    hir_semantic_parent[row] =
        blocked_search_last_before<uint, uint, SemanticEndTree, SemanticEndPast>(row, row);
}
