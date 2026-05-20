import prefix_scan;
import scatter;

public interface ISegmentRowPredicate
{
    static bool keep(uint row);
}

public interface ISegmentScatterEmitter<TContext>
{
    static bool keep(uint row);
    static void store(uint dst, uint row, uint local_i, TContext context);
}

public struct SegmentScatterResult
{
    public uint matched;
    public uint stored;
    public uint first_oob_dst;
}

public SegmentScatterResult segment_scatter_result(
    uint matched,
    uint stored,
    uint first_oob_dst)
{
    SegmentScatterResult result;
    result.matched = matched;
    result.stored = stored;
    result.first_oob_dst = first_oob_dst;
    return result;
}

public uint segment_length(uint begin, uint end)
{
    return end > begin ? end - begin : 0u;
}

public uint count_segment_rows_if<TPredicate: ISegmentRowPredicate>(uint begin, uint end)
{
    uint count = 0u;
    [loop]
    for (uint row = begin; row < end; row += 1u)
    {
        if (TPredicate.keep(row))
            count += 1u;
    }
    return count;
}

public bool segment_has_rows(uint begin, uint end)
{
    return end > begin;
}

public SegmentScatterResult scatter_segment_rows_if<
    TContext,
    TEmitter: ISegmentScatterEmitter<TContext>>(
    uint begin,
    uint end,
    uint dst_prefix,
    uint capacity,
    TContext context,
    uint invalid)
{
    uint matched = 0u;
    uint stored = 0u;
    uint first_oob_dst = invalid;

    [loop]
    for (uint row = begin; row < end; row += 1u)
    {
        if (!TEmitter.keep(row))
            continue;

        uint dst = segment_item_dst(dst_prefix, matched);
        matched += 1u;
        if (!scatter_dst_in_bounds(dst, capacity))
        {
            if (first_oob_dst == invalid)
                first_oob_dst = dst;
            continue;
        }

        TEmitter.store(dst, row, matched - 1u, context);
        stored += 1u;
    }

    return segment_scatter_result(matched, stored, first_oob_dst);
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
