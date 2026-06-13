import prefix_scan;

public uint segment_length(uint begin, uint end)
{
    return end > begin ? end - begin : 0u;
}

public bool segment_has_rows(uint begin, uint end)
{
    return end > begin;
}

public uint segment_head_flag(bool starts_segment)
{
    return starts_segment ? 1u : 0u;
}

public bool segment_is_head(uint segment_head)
{
    return segment_head != 0u;
}

public bool segment_is_tail(uint lane, uint active_count, uint next_segment_head)
{
    if (lane >= active_count)
        return false;
    return lane + 1u >= active_count || segment_is_head(next_segment_head);
}

public inline T segmented_scan_inclusive<
    T,
    TOp: IPrefixScanOp<T>,
    let GSIZE: int>(
    uint lane,
    T value,
    uint segment_head,
    inout T scan_values[GSIZE],
    inout uint scan_heads[GSIZE])
{
    scan_values[lane] = value;
    scan_heads[lane] = segment_head != 0u ? 1u : 0u;
    GroupMemoryBarrierWithGroupSync();

    for (uint offs = 1u; offs < uint(GSIZE); offs <<= 1u)
    {
        T right_value = scan_values[lane];
        uint right_head = scan_heads[lane];
        T left_value = TOp.identity();
        uint left_head = 0u;
        if (lane >= offs)
        {
            left_value = scan_values[lane - offs];
            left_head = scan_heads[lane - offs];
        }
        GroupMemoryBarrierWithGroupSync();

        if (lane >= offs && right_head == 0u)
        {
            right_value = TOp.combine(left_value, right_value);
            right_head = left_head;
        }
        scan_values[lane] = right_value;
        scan_heads[lane] = right_head;
        GroupMemoryBarrierWithGroupSync();
    }

    return scan_values[lane];
}

public inline void segmented_scan_prefixes<
    T,
    TOp: IPrefixScanOp<T>,
    let GSIZE: int>(
    uint lane,
    T value,
    uint segment_head,
    inout T scan_values[GSIZE],
    inout uint scan_heads[GSIZE],
    out T inclusive,
    out T exclusive)
{
    inclusive = segmented_scan_inclusive<T, TOp, GSIZE>(
        lane,
        value,
        segment_head,
        scan_values,
        scan_heads);

    if (lane == 0u || segment_is_head(segment_head))
        exclusive = TOp.identity();
    else
        exclusive = scan_values[lane - 1u];
}

public inline T segmented_scan_exclusive<
    T,
    TOp: IPrefixScanOp<T>,
    let GSIZE: int>(
    uint lane,
    T value,
    uint segment_head,
    inout T scan_values[GSIZE],
    inout uint scan_heads[GSIZE])
{
    T inclusive;
    T exclusive;
    segmented_scan_prefixes<T, TOp, GSIZE>(
        lane,
        value,
        segment_head,
        scan_values,
        scan_heads,
        inclusive,
        exclusive);
    return exclusive;
}

public inline T segment_total_or_identity<T, TOp: IPrefixScanOp<T>>(
    bool segment_tail,
    T inclusive)
{
    return segment_tail ? inclusive : TOp.identity();
}
