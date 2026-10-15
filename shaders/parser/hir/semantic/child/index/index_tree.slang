// Range (minimum, count) heaps over the dense semantic parents.
//
// Rows are in preorder, so every row strictly between a parent p and its
// child r lies in p's subtree and has a parent of at least p; exactly p's
// earlier children have parent p. Row r's child index is therefore the
// number of times the minimum of parent + 1 occurs in (p, r), when that
// minimum is p + 1. Roots wrap parent + 1 to 0, so a root's index counts the
// earlier roots in [0, r).
//
// The heaps use the semantic-end layout (parent/end_tree.slang): index_rows
// builds one local heap per 256-row block, index_blocks one per group of 256
// blocks, and index_top the heap over the groups. Entries hold
// (minimum, occurrences).

import prefix_scan;

public static const uint CHILD_INDEX_FANOUT = 256u;

public struct ChildIndexMinCount : IPrefixScanOp<uint2>
{
    public static uint2 identity()
    {
        return uint2(0xffffffffu, 0u);
    }

    public static uint2 combine(uint2 left, uint2 right)
    {
        if (left.x < right.x)
            return left;
        if (right.x < left.x)
            return right;
        return uint2(left.x, left.y + right.y);
    }
}

// A row's heap leaf: parent + 1 once (an invalid parent wraps to 0).
public uint2 child_index_leaf(uint parent)
{
    return uint2(parent + 1u, 1u);
}
