public static const uint SORTED_RUN_INVALID = 0xffffffffu;

public interface ISortedRunEquality
{
    static bool equal(uint left_item, uint right_item);
}

public uint sorted_run_head_flag(bool equal_previous)
{
    return equal_previous ? 0u : 1u;
}

public uint sorted_run_id_from_head_prefix(uint run_head, uint exclusive_run_head_prefix)
{
    if (run_head != 0u)
        return exclusive_run_head_prefix;
    if (exclusive_run_head_prefix == 0u)
        return 0u;
    return exclusive_run_head_prefix - 1u;
}

public uint sorted_run_count_from_last_id(bool has_items, uint last_run_id)
{
    return has_items ? last_run_id + 1u : 0u;
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

public bool sorted_identity_item(
    uint sorted_i,
    uint sorted_count,
    uint item_capacity,
    out uint item)
{
    item = SORTED_RUN_INVALID;
    if (sorted_i >= sorted_count || sorted_i >= item_capacity)
        return false;
    item = sorted_i;
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

public bool sorted_identity_adjacent_duplicate<TEq: ISortedRunEquality>(
    uint sorted_i,
    uint sorted_count,
    uint item_capacity,
    out uint item,
    out uint previous_item)
{
    previous_item = SORTED_RUN_INVALID;
    if (!sorted_identity_item(sorted_i, sorted_count, item_capacity, item))
        return false;
    if (sorted_i == 0u)
        return false;
    if (!sorted_identity_item(sorted_i - 1u, sorted_count, item_capacity, previous_item))
        return false;
    return TEq.equal(previous_item, item);
}

public bool sorted_run_head<TEq: ISortedRunEquality>(
    uint sorted_i,
    uint sorted_count,
    uint item_capacity,
    StructuredBuffer<uint> sorted_order,
    out uint item)
{
    uint previous_item;
    if (!sorted_order_item(sorted_i, sorted_count, item_capacity, sorted_order, item))
        return false;
    if (sorted_i == 0u)
        return true;
    if (!sorted_order_item(
        sorted_i - 1u,
        sorted_count,
        item_capacity,
        sorted_order,
        previous_item))
        return true;
    return !TEq.equal(previous_item, item);
}

public bool sorted_run_tail<TEq: ISortedRunEquality>(
    uint sorted_i,
    uint sorted_count,
    uint item_capacity,
    StructuredBuffer<uint> sorted_order,
    out uint item)
{
    uint next_item;
    if (!sorted_order_item(sorted_i, sorted_count, item_capacity, sorted_order, item))
        return false;
    if (sorted_i + 1u >= sorted_count)
        return true;
    if (!sorted_order_item(sorted_i + 1u, sorted_count, item_capacity, sorted_order, next_item))
        return true;
    return !TEq.equal(item, next_item);
}

public bool sorted_identity_run_head<TEq: ISortedRunEquality>(
    uint sorted_i,
    uint sorted_count,
    uint item_capacity,
    out uint item)
{
    uint previous_item;
    if (!sorted_identity_item(sorted_i, sorted_count, item_capacity, item))
        return false;
    if (sorted_i == 0u)
        return true;
    if (!sorted_identity_item(sorted_i - 1u, sorted_count, item_capacity, previous_item))
        return true;
    return !TEq.equal(previous_item, item);
}

public bool sorted_identity_run_tail<TEq: ISortedRunEquality>(
    uint sorted_i,
    uint sorted_count,
    uint item_capacity,
    out uint item)
{
    uint next_item;
    if (!sorted_identity_item(sorted_i, sorted_count, item_capacity, item))
        return false;
    if (sorted_i + 1u >= sorted_count)
        return true;
    if (!sorted_identity_item(sorted_i + 1u, sorted_count, item_capacity, next_item))
        return true;
    return !TEq.equal(item, next_item);
}
