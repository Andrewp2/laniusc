public interface IFixedU32RowKey<TKey>
{
    static uint row_lane(uint row, uint lane);
    static uint key_lane(TKey key, uint lane);
}

static const uint FIXED_U32_KEY_MAX_LANES = 16u;

public int fixed_u32_lane_compare(uint left, uint right)
{
    if (left < right)
        return -1;
    if (left > right)
        return 1;
    return 0;
}

public int fixed_u32_row_key_compare<
    TKey,
    TOps: IFixedU32RowKey<TKey>>(
    uint row,
    TKey key,
    uint lane_count)
{
    [loop]
    for (uint lane = 0u; lane < FIXED_U32_KEY_MAX_LANES; lane += 1u)
    {
        if (lane >= lane_count)
            return 0;
        int cmp = fixed_u32_lane_compare(
            TOps.row_lane(row, lane),
            TOps.key_lane(key, lane));
        if (cmp != 0)
            return cmp;
    }
    return lane_count > FIXED_U32_KEY_MAX_LANES ? 1 : 0;
}

public bool fixed_u32_row_key_equal<
    TKey,
    TOps: IFixedU32RowKey<TKey>>(
    uint row,
    TKey key,
    uint lane_count)
{
    return fixed_u32_row_key_compare<TKey, TOps>(row, key, lane_count) == 0;
}

public uint fixed_key_encode_nullable_u32(uint value, uint invalid)
{
    return value == invalid ? 0u : value + 1u;
}
