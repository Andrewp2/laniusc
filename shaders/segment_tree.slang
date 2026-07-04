import fixed.stack;

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

public struct RangeSearchU32BitsetIntersects : IRangeSearchPredicate<uint, uint>
{
    public static bool aggregate_may_match(uint aggregate, uint query)
    {
        return (aggregate & query) != 0u;
    }

    public static bool leaf_matches(uint leaf, uint query)
    {
        return (leaf & query) != 0u;
    }
}

static const int RANGE_SEARCH_TREE_SEARCH_STACK = 64;
// Local helper budgets: callers must bound tree frames by the fixed stack and
// row scans by one published row block before using these loops.
static const uint RANGE_SEARCH_TREE_POP_BUDGET = 256u;
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

public struct RangeSearchTreeFrame
{
    uint node;
    uint l;
    uint r;
}

public RangeSearchTreeFrame range_search_tree_frame(uint node, uint l, uint r)
{
    RangeSearchTreeFrame frame;
    frame.node = node;
    frame.l = l;
    frame.r = r;
    return frame;
}

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
    if (lo_block >= n || leaf_base == 0u)
        return false;

    RangeSearchTreeFrame stack[RANGE_SEARCH_TREE_SEARCH_STACK];
    uint sp = 0u;

    if (!fixed_stack_push<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
            sp,
            stack,
            range_search_tree_frame(1u, 0u, leaf_base)))
        return false;

    for (uint pop_count = 0u; pop_count < RANGE_SEARCH_TREE_POP_BUDGET; pop_count += 1u)
    {
        if (fixed_stack_empty(sp))
            return false;

        RangeSearchTreeFrame frame;
        if (!fixed_stack_pop<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
                sp,
                stack,
                frame,
                range_search_tree_frame(RANGE_SEARCH_TREE_INVALID, 0u, 0u)))
            return false;
        uint node = frame.node;
        uint l = frame.l;
        uint r = frame.r;

        if (r <= lo_block || l >= n)
            continue;

        bool fully_in_range = l >= lo_block;
        if (fully_in_range && !TPredicate.aggregate_may_match(TTree.tree_value(node), query))
            continue;

        if (r - l == 1u)
        {
            if (l >= lo_block && l < n && TPredicate.leaf_matches(TTree.leaf_value(l), query))
            {
                block = l;
                return true;
            }
            continue;
        }

        if (sp + 2u > uint(RANGE_SEARCH_TREE_SEARCH_STACK))
            return false;

        uint mid = (l + r) >> 1u;

        if (!fixed_stack_push<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
                sp,
                stack,
                range_search_tree_frame(node * 2u + 1u, mid, r)) ||
            !fixed_stack_push<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
                sp,
                stack,
                range_search_tree_frame(node * 2u, l, mid)))
            return false;
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

    RangeSearchTreeFrame stack[RANGE_SEARCH_TREE_SEARCH_STACK];
    uint sp = 0u;

    if (!fixed_stack_push<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
            sp,
            stack,
            range_search_tree_frame(1u, 0u, leaf_base)))
        return false;

    for (uint pop_count = 0u; pop_count < RANGE_SEARCH_TREE_POP_BUDGET; pop_count += 1u)
    {
        if (fixed_stack_empty(sp))
            return false;

        RangeSearchTreeFrame frame;
        if (!fixed_stack_pop<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
                sp,
                stack,
                frame,
                range_search_tree_frame(RANGE_SEARCH_TREE_INVALID, 0u, 0u)))
            return false;
        uint node = frame.node;
        uint l = frame.l;
        uint r = frame.r;

        if (l >= hi_block || l >= n)
            continue;

        bool fully_in_range = r <= hi_block;
        if (fully_in_range && !TPredicate.aggregate_may_match(TTree.tree_value(node), query))
            continue;

        if (r - l == 1u)
        {
            if (l < hi_block && l < n && TPredicate.leaf_matches(TTree.leaf_value(l), query))
            {
                block = l;
                return true;
            }
            continue;
        }

        if (sp + 2u > uint(RANGE_SEARCH_TREE_SEARCH_STACK))
            return false;

        uint mid = (l + r) >> 1u;

        if (!fixed_stack_push<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
                sp,
                stack,
                range_search_tree_frame(node * 2u, l, mid)) ||
            !fixed_stack_push<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
                sp,
                stack,
                range_search_tree_frame(node * 2u + 1u, mid, r)))
            return false;
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

    uint capped_hi = min(hi_block, n);
    if (capped_hi <= lo_block)
        return false;

    RangeSearchTreeFrame stack[RANGE_SEARCH_TREE_SEARCH_STACK];
    uint sp = 0u;

    if (!fixed_stack_push<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
            sp,
            stack,
            range_search_tree_frame(1u, 0u, leaf_base)))
        return false;

    for (uint pop_count = 0u; pop_count < RANGE_SEARCH_TREE_POP_BUDGET; pop_count += 1u)
    {
        if (fixed_stack_empty(sp))
            return false;

        RangeSearchTreeFrame frame;
        if (!fixed_stack_pop<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
                sp,
                stack,
                frame,
                range_search_tree_frame(RANGE_SEARCH_TREE_INVALID, 0u, 0u)))
            return false;
        uint node = frame.node;
        uint l = frame.l;
        uint r = frame.r;

        if (r <= lo_block || l >= capped_hi || l >= n)
            continue;

        bool fully_in_range = l >= lo_block && r <= capped_hi;
        if (fully_in_range && !TPredicate.aggregate_may_match(TTree.tree_value(node), query))
            continue;

        if (r - l == 1u)
        {
            if (l >= lo_block && l < capped_hi && l < n &&
                TPredicate.leaf_matches(TTree.leaf_value(l), query))
            {
                block = l;
                return true;
            }
            continue;
        }

        if (sp + 2u > uint(RANGE_SEARCH_TREE_SEARCH_STACK))
            return false;

        uint mid = (l + r) >> 1u;

        if (!fixed_stack_push<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
                sp,
                stack,
                range_search_tree_frame(node * 2u, l, mid)) ||
            !fixed_stack_push<RangeSearchTreeFrame, RANGE_SEARCH_TREE_SEARCH_STACK>(
                sp,
                stack,
                range_search_tree_frame(node * 2u + 1u, mid, r)))
            return false;
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

    uint candidate_block;
    if (!range_search_tree_last_block_before<TValue, TQuery, TTree, TPredicate>(
            block,
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
