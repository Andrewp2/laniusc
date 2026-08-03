public static const uint SORTED_RUN_INVALID = 0xffffffffu;

public interface ISortedRunEquality
{
    static bool equal(uint left_item, uint right_item);
}

public bool sorted_order_item(
    uint sorted_i,
    uint sorted_count,
    uint item_capacity,
    StructuredBuffer<uint> sorted_order,
    out uint item)
{
    item = SORTED_RUN_INVALID;
    if (sorted_i >= sorted_count)
        return false;

    uint candidate = sorted_order[sorted_i];
    if (candidate >= item_capacity)
        return false;

    item = candidate;
    return true;
}

public bool sorted_adjacent_duplicate<TEq: ISortedRunEquality>(
    uint sorted_i,
    uint sorted_count,
    uint item_capacity,
    StructuredBuffer<uint> sorted_order,
    out uint item,
    out uint previous_item)
{
    previous_item = SORTED_RUN_INVALID;
    if (!sorted_order_item(sorted_i, sorted_count, item_capacity, sorted_order, item))
        return false;
    if (sorted_i == 0u)
        return false;
    if (!sorted_order_item(
        sorted_i - 1u,
        sorted_count,
        item_capacity,
        sorted_order,
        previous_item))
        return false;
    return TEq.equal(previous_item, item);
}
