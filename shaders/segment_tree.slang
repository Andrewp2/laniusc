public interface IRangeSearchTree<T>
{
    static uint n_blocks();
    static uint leaf_base();
    static T leaf_value(uint block);
    static T tree_value(uint node);
}

public interface IRangeSearchPredicate<TValue, TQuery>
{
    static bool aggregate_may_match(TValue aggregate, TQuery query);
    static bool leaf_matches(TValue leaf, TQuery query);
}

public interface IRangeSearchRows<TValue>
{
    static uint item_count();
    static uint block_size();
    static TValue row_value(uint row);
}

public struct RangeSearchI32AtLeast : IRangeSearchPredicate<int, int>
{
    public static bool aggregate_may_match(int aggregate, int query)
    {
        return aggregate >= query;
    }

    public static bool leaf_matches(int leaf, int query)
    {
        return leaf >= query;
    }
}

// Local helper budget: callers must bound row scans by one published row
// block before using these loops.
static const uint RANGE_SEARCH_ROW_BLOCK_SCAN_BUDGET = 256u;
static const uint RANGE_SEARCH_TREE_INVALID = 0xffffffffu;

public uint range_search_leaf_base_for_block_count(uint block_count)
{
    uint value = max(block_count, 1u);
    value -= 1u;
    value |= value >> 1u;
    value |= value >> 2u;
    value |= value >> 4u;
    value |= value >> 8u;
    value |= value >> 16u;
    return value + 1u;
}

// The block searches below walk the implicit heap (root 1, children 2v and
// 2v + 1, block b's leaf at leaf_base + b, leaf_base a power of two) without
// a stack. A walk visits the maximal heap nodes inside the queried block
// range in search order, enters a node only when its aggregate may match,
// and when a node fails moves to the next node in that order: up through the
// ancestors it is the last child of, then across to the adjacent sibling.
// Each node is tracked with its first block `l` and width `w`. Nodes that
// only partly overlap the range are entered without an aggregate test, and
// a leaf must pass both its aggregate and its leaf value, which is the same
// rule the previous depth-first stack search applied.

public bool range_search_tree_first_block_at_or_after<
    TValue,
    TQuery,
    TTree: IRangeSearchTree<TValue>,
    TPredicate: IRangeSearchPredicate<TValue, TQuery>>(
    uint lo_block,
    TQuery query,
    out uint block)
{
    block = RANGE_SEARCH_TREE_INVALID;
    uint n = TTree.n_blocks();
    uint leaf_base = TTree.leaf_base();
    if (lo_block >= n || leaf_base == 0u || lo_block >= leaf_base)
        return false;

    // The largest node whose first block is lo_block.
    uint v = leaf_base + lo_block;
    uint l = lo_block;
    uint w = 1u;
    while (v > 1u && (v & 1u) == 0u)
    {
        v >>= 1u;
        w <<= 1u;
    }

    for (;;)
    {
        // Later nodes start further right, so none of them holds a block.
        if (l >= n)
            return false;

        bool enter = TPredicate.aggregate_may_match(TTree.tree_value(v), query);
        if (enter && w == 1u)
        {
            if (TPredicate.leaf_matches(TTree.leaf_value(l), query))
            {
                block = l;
                return true;
            }
            enter = false;
        }
        if (enter)
        {
            v <<= 1u;
            w >>= 1u;
            continue;
        }

        // Next node to the right: climb while v is a right child.
        while ((v & 1u) != 0u)
        {
            if (v == 1u)
                return false;
            v >>= 1u;
            l -= w;
            w <<= 1u;
        }
        v += 1u;
        l += w;
    }
    return false;
}

public bool range_search_tree_last_block_before<
    TValue,
    TQuery,
    TTree: IRangeSearchTree<TValue>,
    TPredicate: IRangeSearchPredicate<TValue, TQuery>>(
    uint hi_block,
    TQuery query,
    out uint block)
{
    block = RANGE_SEARCH_TREE_INVALID;
    uint n = TTree.n_blocks();
    uint leaf_base = TTree.leaf_base();
    if (hi_block == 0u || n == 0u || leaf_base == 0u)
        return false;

    // The largest node whose last block is hi - 1.
    uint hi = min(hi_block, leaf_base);
    uint v = leaf_base + hi - 1u;
    uint l = hi - 1u;
    uint w = 1u;
    while (v > 1u && (v & 1u) != 0u)
    {
        v >>= 1u;
        l -= w;
        w <<= 1u;
    }

    for (;;)
    {
        // Nodes starting at or past n hold no block; skip them.
        bool enter = l < n && TPredicate.aggregate_may_match(TTree.tree_value(v), query);
        if (enter && w == 1u)
        {
            if (TPredicate.leaf_matches(TTree.leaf_value(l), query))
            {
                block = l;
                return true;
            }
            enter = false;
        }
        if (enter)
        {
            v = v * 2u + 1u;
            w >>= 1u;
            l += w;
            continue;
        }

        // Next node to the left: climb while v is a left child.
        while ((v & 1u) == 0u)
        {
            v >>= 1u;
            w <<= 1u;
        }
        if (v == 1u)
            return false;
        v -= 1u;
        l -= w;
    }
    return false;
}

public bool range_search_tree_last_block_between<
    TValue,
    TQuery,
    TTree: IRangeSearchTree<TValue>,
    TPredicate: IRangeSearchPredicate<TValue, TQuery>>(
    uint lo_block,
    uint hi_block,
    TQuery query,
    out uint block)
{
    block = RANGE_SEARCH_TREE_INVALID;
    uint n = TTree.n_blocks();
    uint leaf_base = TTree.leaf_base();
    if (hi_block <= lo_block || n == 0u || leaf_base == 0u)
        return false;

    uint capped_hi = min(min(hi_block, n), leaf_base);
    if (capped_hi <= lo_block)
        return false;

    // The largest node whose last block is capped_hi - 1.
    uint v = leaf_base + capped_hi - 1u;
    uint l = capped_hi - 1u;
    uint w = 1u;
    while (v > 1u && (v & 1u) != 0u)
    {
        v >>= 1u;
        l -= w;
        w <<= 1u;
    }

    for (;;)
    {
        // Every later node ends at or before this one's first block.
        if (l + w <= lo_block)
            return false;

        // A node that straddles lo_block is entered without a test; it is
        // never a leaf, because a leaf that ends after lo_block starts there.
        bool enter = l < lo_block || TPredicate.aggregate_may_match(TTree.tree_value(v), query);
        if (enter && w == 1u)
        {
            if (TPredicate.leaf_matches(TTree.leaf_value(l), query))
            {
                block = l;
                return true;
            }
            enter = false;
        }
        if (enter)
        {
            v = v * 2u + 1u;
            w >>= 1u;
            l += w;
            continue;
        }

        // Next node to the left: climb while v is a left child.
        while ((v & 1u) == 0u)
        {
            v >>= 1u;
            w <<= 1u;
        }
        if (v == 1u)
            return false;
        v -= 1u;
        l -= w;
    }
    return false;
}

public bool range_search_first_index_in_block_at_or_after<
    TValue,
    TQuery,
    TRows: IRangeSearchRows<TValue>,
    TPredicate: IRangeSearchPredicate<TValue, TQuery>>(
    uint lo_index,
    uint block,
    TQuery query,
    out uint index)
{
    index = RANGE_SEARCH_TREE_INVALID;
    uint block_size = TRows.block_size();
    uint count = TRows.item_count();
    if (block_size == 0u || block_size > RANGE_SEARCH_ROW_BLOCK_SCAN_BUDGET || lo_index >= count)
        return false;

    uint start = max(lo_index, block * block_size);
    uint end = min(count, (block + 1u) * block_size);
    uint span = (end > start) ? (end - start) : 0u;
    for (uint offset = 0u; offset < RANGE_SEARCH_ROW_BLOCK_SCAN_BUDGET; offset += 1u)
    {
        if (offset >= span)
            continue;

        uint row = start + offset;
        if (TPredicate.leaf_matches(TRows.row_value(row), query))
        {
            index = row;
            return true;
        }
    }
    return false;
}

public bool range_search_last_index_in_block_before<
    TValue,
    TQuery,
    TRows: IRangeSearchRows<TValue>,
    TPredicate: IRangeSearchPredicate<TValue, TQuery>>(
    uint hi_index,
    uint block,
    TQuery query,
    out uint index)
{
    index = RANGE_SEARCH_TREE_INVALID;
    uint block_size = TRows.block_size();
    uint count = TRows.item_count();
    if (block_size == 0u || block_size > RANGE_SEARCH_ROW_BLOCK_SCAN_BUDGET || hi_index == 0u ||
        count == 0u)
        return false;

    uint start = block * block_size;
    uint end = min(count, (block + 1u) * block_size);
    uint scan_end = min(hi_index, end);
    uint span = (scan_end > start) ? (scan_end - start) : 0u;
    for (uint offset = 0u; offset < RANGE_SEARCH_ROW_BLOCK_SCAN_BUDGET; offset += 1u)
    {
        if (offset >= span)
            continue;

        uint row = scan_end - 1u - offset;
        if (TPredicate.leaf_matches(TRows.row_value(row), query))
        {
            index = row;
            return true;
        }
    }
    return false;
}

public bool range_search_last_index_in_block_between<
    TValue,
    TQuery,
    TRows: IRangeSearchRows<TValue>,
    TPredicate: IRangeSearchPredicate<TValue, TQuery>>(
    uint lo_index,
    uint hi_index,
    uint block,
    TQuery query,
    out uint index)
{
    index = RANGE_SEARCH_TREE_INVALID;
    uint block_size = TRows.block_size();
    uint count = TRows.item_count();
    if (block_size == 0u || block_size > RANGE_SEARCH_ROW_BLOCK_SCAN_BUDGET ||
        hi_index <= lo_index || count == 0u)
        return false;

    uint start = max(lo_index, block * block_size);
    uint end = min(min(hi_index, count), (block + 1u) * block_size);
    uint span = (end > start) ? (end - start) : 0u;
    for (uint offset = 0u; offset < RANGE_SEARCH_ROW_BLOCK_SCAN_BUDGET; offset += 1u)
    {
        if (offset >= span)
            continue;

        uint row = end - 1u - offset;
        if (TPredicate.leaf_matches(TRows.row_value(row), query))
        {
            index = row;
            return true;
        }
    }
    return false;
}

public bool range_search_tree_first_index_at_or_after<
    TValue,
    TQuery,
    TTree: IRangeSearchTree<TValue>,
    TRows: IRangeSearchRows<TValue>,
    TPredicate: IRangeSearchPredicate<TValue, TQuery>>(
    uint lo_index,
    TQuery query,
    out uint index)
{
    index = RANGE_SEARCH_TREE_INVALID;
    uint block_size = TRows.block_size();
    uint count = TRows.item_count();
    if (block_size == 0u || lo_index >= count)
        return false;

    uint block = lo_index / block_size;
    if (range_search_first_index_in_block_at_or_after<TValue, TQuery, TRows, TPredicate>(
            lo_index,
            block,
            query,
            index))
        return true;

    uint candidate_block;
    if (!range_search_tree_first_block_at_or_after<TValue, TQuery, TTree, TPredicate>(
            block + 1u,
            query,
            candidate_block))
        return false;

    return range_search_first_index_in_block_at_or_after<TValue, TQuery, TRows, TPredicate>(
        candidate_block * block_size,
        candidate_block,
        query,
        index);
}

public bool range_search_tree_last_index_before<
    TValue,
    TQuery,
    TTree: IRangeSearchTree<TValue>,
    TRows: IRangeSearchRows<TValue>,
    TPredicate: IRangeSearchPredicate<TValue, TQuery>>(
    uint hi_index,
    TQuery query,
    out uint index)
{
    index = RANGE_SEARCH_TREE_INVALID;
    uint block_size = TRows.block_size();
    uint count = TRows.item_count();
    if (block_size == 0u || hi_index == 0u || count == 0u)
        return false;

    uint capped_hi = min(hi_index, count);
    uint block = (capped_hi - 1u) / block_size;
    if (range_search_last_index_in_block_before<TValue, TQuery, TRows, TPredicate>(
            capped_hi,
            block,
            query,
            index))
        return true;

    // The adjacent block is both the common cross-block case and the only
    // block whose row data is needed before consulting the hierarchy. Search
    // it directly, then exclude it from the tree query. Besides avoiding a
    // tree traversal for short delimiter spans, this makes the block/row
    // boundary identical to the same-block path.
    if (block > 0u &&
        range_search_last_index_in_block_before<TValue, TQuery, TRows, TPredicate>(
            block * block_size,
            block - 1u,
            query,
            index))
        return true;

    uint candidate_block;
    if (!range_search_tree_last_block_before<TValue, TQuery, TTree, TPredicate>(
            block > 0u ? block - 1u : 0u,
            query,
            candidate_block))
        return false;

    return range_search_last_index_in_block_before<TValue, TQuery, TRows, TPredicate>(
        (candidate_block + 1u) * block_size,
        candidate_block,
        query,
        index);
}

public bool range_search_tree_last_index_between<
    TValue,
    TQuery,
    TTree: IRangeSearchTree<TValue>,
    TRows: IRangeSearchRows<TValue>,
    TPredicate: IRangeSearchPredicate<TValue, TQuery>>(
    uint lo_index,
    uint hi_index,
    TQuery query,
    out uint index)
{
    index = RANGE_SEARCH_TREE_INVALID;
    uint block_size = TRows.block_size();
    uint count = TRows.item_count();
    if (block_size == 0u || hi_index <= lo_index || count == 0u)
        return false;

    uint capped_hi = min(hi_index, count);
    if (capped_hi <= lo_index)
        return false;

    uint hi_block = (capped_hi - 1u) / block_size;
    if (range_search_last_index_in_block_between<TValue, TQuery, TRows, TPredicate>(
            lo_index,
            capped_hi,
            hi_block,
            query,
            index))
        return true;

    uint lo_block = lo_index / block_size;
    if (hi_block <= lo_block)
        return false;

    uint candidate_block;
    if (!range_search_tree_last_block_between<TValue, TQuery, TTree, TPredicate>(
            lo_block,
            hi_block,
            query,
            candidate_block))
        return false;

    return range_search_last_index_in_block_between<TValue, TQuery, TRows, TPredicate>(
        lo_index,
        (candidate_block + 1u) * block_size,
        candidate_block,
        query,
        index);
}
