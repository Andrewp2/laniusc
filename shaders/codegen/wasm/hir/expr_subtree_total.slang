// Publish every expression node's byte/error total from the forest postorder.
//
// For a postorder row at depth d, its subtree begins immediately after the
// previous row in the same forest with depth <= d. The block-minimum tree and
// range search solve that previous-smaller-or-equal query for all nodes in
// parallel, independent of argument count and expression depth. Validators and
// byte scatters can therefore query semantic subtree sizes without walking HIR.

import segment_tree;

struct Params { uint n_items; uint n_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gExprRadix;

struct TreeParams
{
    uint n_blocks;
    uint leaf_base;
    uint start_node;
    uint node_count;
    uint mode;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<TreeParams> gExprDepthTree;

StructuredBuffer<uint> hir_expr_forest_root_node;
StructuredBuffer<uint> expr_order;
StructuredBuffer<uint2> expr_root_order_range;
StructuredBuffer<uint2> expr_depth_state;
StructuredBuffer<uint> expr_depth_block_min;
StructuredBuffer<uint> expr_depth_min_tree;
StructuredBuffer<uint4> expr_contribution;
StructuredBuffer<uint4> expr_contribution_local_prefix;
StructuredBuffer<uint4> expr_contribution_block_prefix;
RWStructuredBuffer<uint2> expr_subtree_total;
RWStructuredBuffer<uint2> expr_subtree_features;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

public struct DepthAtMost : IRangeSearchPredicate<uint, uint>
{
    public static bool aggregate_may_match(uint aggregate, uint query)
    {
        return aggregate <= query;
    }

    public static bool leaf_matches(uint leaf, uint query)
    {
        return leaf <= query;
    }
}

public struct ExprDepthMinTree : IRangeSearchTree<uint>
{
    public static uint n_blocks() { return gExprDepthTree.n_blocks; }
    public static uint leaf_base() { return gExprDepthTree.leaf_base; }
    public static uint leaf_value(uint block) { return expr_depth_block_min[block]; }
    public static uint tree_value(uint node) { return expr_depth_min_tree[node]; }
}

public struct ExprDepthRows : IRangeSearchRows<uint>
{
    public static uint item_count() { return gExprRadix.n_items; }
    public static uint block_size() { return WG_SIZE; }
    public static uint row_value(uint row)
    {
        uint node = expr_order[row];
        return node < gExprRadix.n_items ? expr_depth_state[node].y : INVALID;
    }
}

uint4 prefix_before(uint boundary)
{
    boundary = min(boundary, gExprRadix.n_items);
    if (boundary == 0u)
        return uint4(0u, 0u, 0u, 0u);

    uint item = boundary - 1u;
    uint block = item / WG_SIZE;
    uint4 prior_blocks = block == 0u
        ? uint4(0u, 0u, 0u, 0u)
        : expr_contribution_block_prefix[block - 1u];
    return prior_blocks + expr_contribution_local_prefix[item] + expr_contribution[item];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (row >= gExprRadix.n_items)
        return;

    uint node = expr_order[row];
    if (node >= gExprRadix.n_items)
        return;

    uint root = hir_expr_forest_root_node[node];
    if (root == INVALID || root >= gExprRadix.n_items)
    {
        expr_subtree_total[node] = uint2(0u, 0u);
        expr_subtree_features[node] = uint2(0u, 0u);
        return;
    }

    uint root_start = min(expr_root_order_range[root].x, row);
    uint boundary = INVALID;
    bool found = range_search_tree_last_index_between<
        uint,
        uint,
        ExprDepthMinTree,
        ExprDepthRows,
        DepthAtMost>(root_start, row, expr_depth_state[node].y, boundary);
    uint subtree_start = found ? boundary + 1u : root_start;
    uint4 total = prefix_before(row + 1u) - prefix_before(subtree_start);
    expr_subtree_total[node] = total.xy;
    expr_subtree_features[node] = total.zw;
}
