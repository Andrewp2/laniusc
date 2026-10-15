// Stackless searches over a two-level heap: rows in 256-row blocks, a local
// heap over each block's rows, and one heap over the blocks.
//
// A search climbs from its start row to the nearest heap node that may hold a
// match, then descends from that node to the matching row. It reads
// O(log distance) nodes, needs no per-thread stack, and finds the same row as
// a linear scan.
//
// Local heap of block b: node j in [1, 256) aggregates the rows below it in
// heap numbering (node 1 is the whole block, node j's children are 2j and
// 2j + 1, and leaf 256 + k is row b * 256 + k). A tree stores node j at
// b * 256 + j, and node 1 again at b * 256. The block heap stores block b's
// aggregate at leaf block_leaf_base() + b; its leaves past the last block hold
// a value that never matches.

import segment_tree;
import prefix_scan;

public static const uint BLOCKED_SEARCH_ROWS = 256u;
public static const uint BLOCKED_SEARCH_INVALID = 0xffffffffu;

public interface IBlockedSearchTree<T>
{
    // Rows that may match are [0, row_count()).
    static uint row_count();
    static T row_value(uint row);
    // Local heap node 1 <= node < 256 of block.
    static T local_node(uint block, uint node);
    // Power of two at least the number of blocks.
    static uint block_leaf_base();
    // Block heap node 1 <= node < 2 * block_leaf_base().
    static T block_node(uint node);
}

[ForceInline]
bool blocked_row_matches<
    T,
    Q,
    Tree: IBlockedSearchTree<T>,
    Pred: IRangeSearchPredicate<T, Q>>(uint row, Q query)
{
    return row < Tree.row_count() && Pred.leaf_matches(Tree.row_value(row), query);
}

// Whether local node 1 <= node < 512 of block may hold a match. Nodes from
// 256 on are rows.
bool blocked_local_may_match<
    T,
    Q,
    Tree: IBlockedSearchTree<T>,
    Pred: IRangeSearchPredicate<T, Q>>(uint block, uint node, Q query)
{
    if (node >= BLOCKED_SEARCH_ROWS)
        return blocked_row_matches<T, Q, Tree, Pred>(
            block * BLOCKED_SEARCH_ROWS + (node - BLOCKED_SEARCH_ROWS),
            query);
    return Pred.aggregate_may_match(Tree.local_node(block, node), query);
}

// The last (FIRST: first) matching row under local node `node` of block, which
// may hold a match, or INVALID when the tree disagrees with its rows.
uint blocked_local_descend<
    T,
    Q,
    Tree: IBlockedSearchTree<T>,
    Pred: IRangeSearchPredicate<T, Q>,
    let FIRST: bool>(uint block, uint node, Q query)
{
    for (uint step = 0u; step < 8u; step += 1u)
    {
        if (node >= BLOCKED_SEARCH_ROWS)
            break;
        uint preferred = FIRST ? node * 2u : node * 2u + 1u;
        uint other = FIRST ? preferred + 1u : preferred - 1u;
        node = blocked_local_may_match<T, Q, Tree, Pred>(block, preferred, query)
            ? preferred
            : other;
    }
    uint row = block * BLOCKED_SEARCH_ROWS + (node - BLOCKED_SEARCH_ROWS);
    return blocked_row_matches<T, Q, Tree, Pred>(row, query) ? row : BLOCKED_SEARCH_INVALID;
}

// The last (FIRST: first) block under block heap node `node`, which may hold
// a match, whose aggregate may match.
uint blocked_block_descend<
    T,
    Q,
    Tree: IBlockedSearchTree<T>,
    Pred: IRangeSearchPredicate<T, Q>,
    let FIRST: bool>(uint node, Q query)
{
    uint leaf_base = Tree.block_leaf_base();
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (node >= leaf_base)
            break;
        uint preferred = FIRST ? node * 2u : node * 2u + 1u;
        uint other = FIRST ? preferred + 1u : preferred - 1u;
        node = Pred.aggregate_may_match(Tree.block_node(preferred), query) ? preferred : other;
    }
    return node - leaf_base;
}

// The last row r < hi whose value matches query, or INVALID.
public uint blocked_search_last_before<
    T,
    Q,
    Tree: IBlockedSearchTree<T>,
    Pred: IRangeSearchPredicate<T, Q>>(uint hi, Q query)
{
    uint end = min(hi, Tree.row_count());
    if (end == 0u || !Pred.aggregate_may_match(Tree.block_node(1u), query))
        return BLOCKED_SEARCH_INVALID;

    // Rows of end's block before end: the left siblings on the path from
    // end's leaf to the local root.
    uint block = end / BLOCKED_SEARCH_ROWS;
    uint node = BLOCKED_SEARCH_ROWS + end % BLOCKED_SEARCH_ROWS;
    for (uint step = 0u; step < 8u; step += 1u)
    {
        if ((node & 1u) != 0u &&
            blocked_local_may_match<T, Q, Tree, Pred>(block, node - 1u, query))
            return blocked_local_descend<T, Q, Tree, Pred, false>(block, node - 1u, query);
        node >>= 1u;
    }

    // Earlier blocks: the same climb in the block heap.
    uint leaf_base = Tree.block_leaf_base();
    uint found = 0u;
    if (block >= leaf_base)
    {
        // Every block lies before end; the root may match.
        found = 1u;
    }
    else
    {
        node = leaf_base + block;
        for (uint step = 0u; step < 32u; step += 1u)
        {
            if (node <= 1u)
                break;
            if ((node & 1u) != 0u && Pred.aggregate_may_match(Tree.block_node(node - 1u), query))
            {
                found = node - 1u;
                break;
            }
            node >>= 1u;
        }
    }
    if (found == 0u)
        return BLOCKED_SEARCH_INVALID;

    uint found_block = blocked_block_descend<T, Q, Tree, Pred, false>(found, query);
    return blocked_local_descend<T, Q, Tree, Pred, false>(found_block, 1u, query);
}

// The first row r >= lo whose value matches query, or INVALID.
public uint blocked_search_first_at_or_after<
    T,
    Q,
    Tree: IBlockedSearchTree<T>,
    Pred: IRangeSearchPredicate<T, Q>>(uint lo, Q query)
{
    if (lo >= Tree.row_count() || !Pred.aggregate_may_match(Tree.block_node(1u), query))
        return BLOCKED_SEARCH_INVALID;
    if (blocked_row_matches<T, Q, Tree, Pred>(lo, query))
        return lo;

    // Rows of lo's block after lo: the right siblings on the path from lo's
    // leaf to the local root.
    uint block = lo / BLOCKED_SEARCH_ROWS;
    uint node = BLOCKED_SEARCH_ROWS + lo % BLOCKED_SEARCH_ROWS;
    for (uint step = 0u; step < 8u; step += 1u)
    {
        if ((node & 1u) == 0u &&
            blocked_local_may_match<T, Q, Tree, Pred>(block, node + 1u, query))
            return blocked_local_descend<T, Q, Tree, Pred, true>(block, node + 1u, query);
        node >>= 1u;
    }

    // Later blocks: the same climb in the block heap.
    uint leaf_base = Tree.block_leaf_base();
    if (block >= leaf_base)
        return BLOCKED_SEARCH_INVALID;
    uint found = 0u;
    node = leaf_base + block;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (node <= 1u)
            break;
        if ((node & 1u) == 0u && Pred.aggregate_may_match(Tree.block_node(node + 1u), query))
        {
            found = node + 1u;
            break;
        }
        node >>= 1u;
    }
    if (found == 0u)
        return BLOCKED_SEARCH_INVALID;

    uint found_block = blocked_block_descend<T, Q, Tree, Pred, true>(found, query);
    return blocked_local_descend<T, Q, Tree, Pred, true>(found_block, 1u, query);
}

// Builds the local heap of one block from each lane's row value: afterwards
// nodes[j] holds node j for j in [1, 256), and nodes[256 + lane] the rows.
// Every lane of the 256-lane group must call it; it synchronizes the group.
public void blocked_local_heap_build<T, TOp: IPrefixScanOp<T>>(
    uint lane,
    T value,
    inout T nodes[512])
{
    nodes[BLOCKED_SEARCH_ROWS + lane] = value;
    GroupMemoryBarrierWithGroupSync();
    for (uint width = BLOCKED_SEARCH_ROWS / 2u; width > 0u; width >>= 1u)
    {
        if (lane < width)
        {
            uint node = width + lane;
            nodes[node] = TOp.combine(nodes[node * 2u], nodes[node * 2u + 1u]);
        }
        GroupMemoryBarrierWithGroupSync();
    }
}
