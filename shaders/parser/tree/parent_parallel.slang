// Parallel preorder parent recovery.
//
// The prefix stage computes E[p] = sum_{k < p}(1 - arity[k]). For node i,
// the parent is the nearest previous node j with E[j] >= E[i], found by
// climbing the per-block maximum heaps and the block maximum tree
// (blocked_search_tree.slang). It also zeroes the subtree close counts that
// tree/spans accumulates next.

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

StructuredBuffer<uint> emit_stream;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<int> tree_prefix;
StructuredBuffer<int> prefix_block_max_tree;
StructuredBuffer<int> prefix_local_max;

RWStructuredBuffer<uint> node_kind;
RWStructuredBuffer<uint> parent;
RWStructuredBuffer<uint> tree_depth_close_count;

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
    [ForceInline] public static uint row_count() { return active_node_count(); }
    [ForceInline] public static int row_value(uint row) { return tree_prefix[row]; }
    [ForceInline] public static int local_node(uint block, uint node) { return prefix_local_max[block * WG_SIZE + node]; }
    [ForceInline] public static uint block_leaf_base() { return gTree.max_tree_leaf_base; }
    [ForceInline] public static int block_node(uint node) { return prefix_block_max_tree[node]; }
}

uint find_parent(uint i, uint n)
{
    return blocked_search_last_before<int, int, ParserPrefixTree, RangeSearchI32AtLeast>(
        i,
        tree_prefix[i]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_node_count();

    if (i >= n)
        return;

    uint kind = emit_stream[i];
    node_kind[i] = kind;
    parent[i] = kind == PROD_FILE ? INVALID : find_parent(i, n);
    tree_depth_close_count[i] = 0u;
}
