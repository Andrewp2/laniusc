// Search heaps over dense semantic subtree ends.
//
// The nearest semantic ancestor of dense row r is the last row s < r whose
// dense subtree end lies past r: rows are in preorder, so the rows whose
// spans contain r are exactly r's semantic ancestors. parent/traverse.slang
// finds that row with blocked_search_last_before over three levels of
// maximum heaps:
//
//  - end_rows: one local heap per 256-row block (blocked_search_tree.slang),
//    with the block's maximum at local node 1 and again at block * 256;
//  - end_blocks: one local heap per group of 256 blocks over the block
//    maxima, stored the same way;
//  - end_top: the heap over the group maxima, nodes [1, group count).
//
// Together the last two levels are one heap over the blocks with
// semantic_end_leaf_base() leaves. Rows and blocks past the semantic rows
// hold 0, which no query matches.

import segment_tree;
import prefix_scan;
import blocked_search_tree;

public static const uint SEMANTIC_END_FANOUT = 256u;
public static const uint SEMANTIC_END_FANOUT_LEVELS = 8u;

// Blocks of 256 rows in a table of n rows.
public uint semantic_end_block_capacity(uint n)
{
    return max((n + SEMANTIC_END_FANOUT - 1u) / SEMANTIC_END_FANOUT, 1u);
}

// Leaves of the heap over the blocks: a power of two, and at least one full
// group so that every heap node maps to a group or the top heap.
public uint semantic_end_leaf_base(uint n)
{
    return range_search_leaf_base_for_block_count(
        max(semantic_end_block_capacity(n), SEMANTIC_END_FANOUT));
}

// Groups of 256 blocks, which are the top heap's leaves.
public uint semantic_end_group_count(uint n)
{
    return semantic_end_leaf_base(n) / SEMANTIC_END_FANOUT;
}

// Matches a subtree end past the queried row.
public struct SemanticEndPast : IRangeSearchPredicate<uint, uint>
{
    public static bool aggregate_may_match(uint aggregate, uint row)
    {
        return aggregate > row;
    }

    public static bool leaf_matches(uint leaf, uint row)
    {
        return leaf > row;
    }
}
