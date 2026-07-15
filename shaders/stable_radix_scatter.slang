import prefix_scan;
import scatter;

static const uint STABLE_RADIX_WG_SIZE = 256u;
static const uint STABLE_RADIX_BUCKET_CAPACITY = 257u;

groupshared uint stable_radix_keys_a[STABLE_RADIX_WG_SIZE];
groupshared uint stable_radix_keys_b[STABLE_RADIX_WG_SIZE];
groupshared uint stable_radix_values_a[STABLE_RADIX_WG_SIZE];
groupshared uint stable_radix_values_b[STABLE_RADIX_WG_SIZE];
groupshared uint stable_radix_scan[STABLE_RADIX_WG_SIZE];
groupshared uint stable_radix_bucket_start[STABLE_RADIX_BUCKET_CAPACITY];

void stable_sort_radix_byte(uint lane, uint key, uint value)
{
    stable_radix_keys_a[lane] = key;
    stable_radix_values_a[lane] = value;
    GroupMemoryBarrierWithGroupSync();

    // Eight stable binary partitions implement one stable u8 radix pass. Each
    // partition obtains its bucket rank from a workgroup prefix scan rather
    // than comparing every lane against every preceding lane.
    for (uint bit = 0u; bit < 8u; bit += 1u)
    {
        bool read_a = (bit & 1u) == 0u;
        uint bit_key = read_a ? stable_radix_keys_a[lane] : stable_radix_keys_b[lane];
        uint bit_value = read_a ? stable_radix_values_a[lane] : stable_radix_values_b[lane];
        uint zero = ((bit_key >> bit) & 1u) == 0u ? 1u : 0u;
        uint inclusive_zero = prefix_scan_inclusive<
            uint,
            PrefixScanU32Add,
            256>(lane, zero, stable_radix_scan);
        uint exclusive_zero = inclusive_zero - zero;
        uint zeros_total = stable_radix_scan[STABLE_RADIX_WG_SIZE - 1u];
        uint ones_before = lane - exclusive_zero;
        uint dst = zero != 0u ? exclusive_zero : zeros_total + ones_before;
        if (read_a)
        {
            stable_radix_keys_b[dst] = bit_key;
            stable_radix_values_b[dst] = bit_value;
        }
        else
        {
            stable_radix_keys_a[dst] = bit_key;
            stable_radix_values_a[dst] = bit_value;
        }
        GroupMemoryBarrierWithGroupSync();
    }
}

public void stable_radix_sort_byte_value(
    uint lane,
    uint key,
    uint value,
    out uint sorted_key,
    out uint sorted_value)
{
    stable_sort_radix_byte(lane, key, value);
    sorted_key = stable_radix_keys_a[lane];
    sorted_value = stable_radix_values_a[lane];
}

public void stable_radix_sort_byte_rank(
    uint lane,
    uint key,
    uint value,
    out uint sorted_key,
    out uint sorted_value,
    out uint local_rank)
{
    stable_sort_radix_byte(lane, key, value);
    sorted_key = stable_radix_keys_a[lane];
    sorted_value = stable_radix_values_a[lane];

    stable_radix_bucket_start[lane] = SCATTER_INACTIVE_KEY;
    if (lane == 0u)
        stable_radix_bucket_start[STABLE_RADIX_BUCKET_CAPACITY - 1u] =
            SCATTER_INACTIVE_KEY;
    GroupMemoryBarrierWithGroupSync();
    bool active = sorted_key != SCATTER_INACTIVE_KEY;
    if (active && (lane == 0u || sorted_key != stable_radix_keys_a[lane - 1u]))
        stable_radix_bucket_start[sorted_key] = lane;
    GroupMemoryBarrierWithGroupSync();
    local_rank = 0u;
    if (active)
        local_rank = lane - stable_radix_bucket_start[sorted_key];
}

public void stable_radix_scatter_block<
    TSource: IStableRadixScatterSource<uint>,
    TSink: IScatterSink<uint>,
    let GSIZE: int>(
    uint block_idx,
    uint lane,
    uint n_blocks,
    uint key_step,
    uint bucket_count,
    StructuredBuffer<uint> radix_bucket_base,
    StructuredBuffer<uint> radix_block_bucket_prefix)
{
    if (block_idx >= n_blocks)
        return;

    uint active_count = TSource.active_count();
    uint order_i = block_idx * uint(GSIZE) + lane;
    bool active = order_i < active_count;
    uint value = active ? TSource.ordered_value(order_i) : TSource.inactive_value();
    uint key = active ? TSource.radix_key(value, key_step) : SCATTER_INACTIVE_KEY;
    stable_sort_radix_byte(lane, key, value);

    key = stable_radix_keys_a[lane];
    value = stable_radix_values_a[lane];
    stable_radix_bucket_start[lane] = SCATTER_INACTIVE_KEY;
    if (lane == 0u)
        stable_radix_bucket_start[STABLE_RADIX_BUCKET_CAPACITY - 1u] =
            SCATTER_INACTIVE_KEY;
    GroupMemoryBarrierWithGroupSync();

    // Some row domains use zero as both a valid row and their inactive value.
    // The full-width sentinel key, not the payload, carries lane activity
    // through the stable local sort.
    active = key != SCATTER_INACTIVE_KEY;
    if (active && (lane == 0u || key != stable_radix_keys_a[lane - 1u]))
        stable_radix_bucket_start[key] = lane;
    GroupMemoryBarrierWithGroupSync();
    if (!active)
        return;

    uint local_rank = lane - stable_radix_bucket_start[key];
    uint prefix_slot = radix_block_bucket_slot(block_idx, key, bucket_count);
    uint block_prefix = radix_block_bucket_prefix[prefix_slot];
    uint dst = stable_radix_dst(radix_bucket_base[key], block_prefix, local_rank);
    scatter_emit<uint, TSink>(dst, active_count, value);
}
