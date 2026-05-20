// Parallel preorder subtree navigation recovery.
//
// For each production node, compute:
// - first_child: first child node index, or INVALID
// - subtree_end: exclusive end index for this node's subtree
// - next_sibling: sibling following this subtree, or INVALID
//
// The prefix stage computes E[p] = sum_{k < p}(1 - arity[k]). The exclusive
// subtree end for node i is the first prefix position p > i where
// E[p] >= E[i] + 1. A max segment tree over prefix-block maxima locates the
// first candidate block in logarithmic work, then the pass scans only that
// block to recover the exact prefix position.

import segment_tree;

struct Params
{
    uint n;
    uint uses_ll1;
    uint n_prefix_blocks;
    uint max_tree_leaf_base;
};
ConstantBuffer<Params> gTree;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> prod_arity;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<int> tree_prefix;
StructuredBuffer<int> prefix_block_max;
StructuredBuffer<int> prefix_block_max_tree;

RWStructuredBuffer<uint> first_child;
RWStructuredBuffer<uint> next_sibling;
RWStructuredBuffer<uint> subtree_end;

static const uint INVALID = 0xFFFFFFFFu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gTree.uses_ll1 != 0u ? min(gTree.n, ll1_status[5u]) : gTree.n;
}

public struct ParserPrefixMaxTree : IRangeSearchTree<int>
{
    public static uint n_blocks()
    {
        return gTree.n_prefix_blocks;
    }

    public static uint leaf_base()
    {
        return gTree.max_tree_leaf_base;
    }

    public static int leaf_value(uint block)
    {
        return prefix_block_max[block];
    }

    public static int tree_value(uint node)
    {
        return prefix_block_max_tree[node];
    }
}

public struct ParserPrefixRows : IRangeSearchRows<int>
{
    public static uint item_count()
    {
        return active_node_count() + 1u;
    }

    public static uint block_size()
    {
        return WG_SIZE;
    }

    public static int row_value(uint row)
    {
        return tree_prefix[row];
    }
}

uint find_subtree_end(uint i, uint n)
{
    int target = tree_prefix[i] + 1;
    uint found;
    if (range_search_tree_first_index_at_or_after<int, int, ParserPrefixMaxTree, ParserPrefixRows, RangeSearchI32AtLeast>(
        i + 1u,
        target,
        found))
        return min(found, n);

    return n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_node_count();
    if (i >= n)
        return;

    uint arity = prod_arity[node_kind[i]];
    first_child[i] = (arity > 0u && i + 1u < n) ? i + 1u : INVALID;

    uint end = find_subtree_end(i, n);
    subtree_end[i] = end;

    next_sibling[i] = (end < n && parent[end] == parent[i]) ? end : INVALID;
}
