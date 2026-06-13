// Parallel preorder parent recovery.
//
// The prefix stage computes E[p] = sum_{k < p}(1 - arity[k]). For node i,
// the parent is the nearest previous node j with E[j] >= E[i]. This pass
// searches inside the current 256-prefix block, then uses a max segment tree to
// find the nearest previous candidate block without walking all intervening
// blocks.

import segment_tree;
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
StructuredBuffer<int> prefix_block_max;
StructuredBuffer<int> prefix_block_max_tree;

RWStructuredBuffer<uint> node_kind;
RWStructuredBuffer<uint> parent;

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
        return active_node_count();
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

uint find_parent(uint i, uint n)
{
    int target = tree_prefix[i];
    uint found;
    if (range_search_tree_last_index_before<int, int, ParserPrefixMaxTree, ParserPrefixRows, RangeSearchI32AtLeast>(
        i,
        target,
        found))
        return found;

    return INVALID;
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
}
