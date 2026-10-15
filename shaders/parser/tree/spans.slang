// Parallel preorder subtree navigation recovery.
//
// For each production node, compute:
// - first_child: first child node index, or INVALID
// - subtree_end: exclusive end index for this node's subtree
// - next_sibling: sibling following this subtree, or INVALID
//
// The prefix stage computes E[p] = sum_{k < p}(1 - arity[k]). The exclusive
// subtree end for node i is the first prefix position p > i where
// E[p] >= E[i] + 1, found by climbing the per-block maximum heaps and the
// block maximum tree (blocked_search_tree.slang).

import segment_tree;
import blocked_search_tree;
import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
    uint n_prefix_blocks;
    uint max_tree_leaf_base;
};
ConstantBuffer<Params> gTree;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> prod_arity;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<int> tree_prefix;
StructuredBuffer<int> prefix_block_max_tree;
StructuredBuffer<int> prefix_local_max;

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
    return gTree.uses_status_count != 0u ? min(gTree.n, tree_count_status[5u]) : gTree.n;
}

public struct ParserPrefixTree : IBlockedSearchTree<int>
{
    [ForceInline] public static uint row_count() { return active_node_count() + 1u; }
    [ForceInline] public static int row_value(uint row) { return tree_prefix[row]; }
    [ForceInline] public static int local_node(uint block, uint node) { return prefix_local_max[block * WG_SIZE + node]; }
    [ForceInline] public static uint block_leaf_base() { return gTree.max_tree_leaf_base; }
    [ForceInline] public static int block_node(uint node) { return prefix_block_max_tree[node]; }
}

uint find_subtree_end(uint i, uint n)
{
    int target = tree_prefix[i] + 1;
    uint found = blocked_search_first_at_or_after<int, int, ParserPrefixTree, RangeSearchI32AtLeast>(
        i + 1u,
        target);
    return found != INVALID ? min(found, n) : n;
}

uint file_root_subtree_end(uint i, uint n)
{
    uint child = i + 1u;
    if (child >= n || parent[child] != i)
        return min(i + 1u, n);

    uint end = find_subtree_end(child, n);
    return end > child && node_kind[end - 1u] == PROD_FILE ? end - 1u : end;
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

    uint end = node_kind[i] == PROD_FILE ? file_root_subtree_end(i, n) : find_subtree_end(i, n);
    subtree_end[i] = end;

    next_sibling[i] = (end < n && parent[end] == parent[i]) ? end : INVALID;
}
