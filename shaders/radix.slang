import atomics;
import byte_packing;
import prefix_scan;

public static const uint RADIX_U8_SENTINEL_BUCKETS = 257u;

public interface IRadixU8KeySource
{
    static uint active_count();
    static uint ordered_row(uint order_i);
    static uint radix_key(uint row, uint key_step);
}

public uint radix_field_index(uint key_step, uint max_field)
{
    return min(key_step / 4u, max_field);
}

public uint radix_reverse_field_index(uint key_step, uint field_count)
{
    uint last_field = field_count == 0u ? 0u : field_count - 1u;
    return last_field - min(key_step / 4u, last_field);
}

public uint radix_byte_key(uint value, uint key_step)
{
    return packed_u8_at(value, key_step);
}

public uint radix_histogram_slot(uint block_idx, uint bucket, uint bucket_count)
{
    return block_idx * bucket_count + bucket;
}

public void clear_radix_histogram_block(
    uint lane,
    uint block_idx,
    uint bucket_count,
    uint workgroup_size,
    RWStructuredBuffer<uint> histogram)
{
    for (uint bucket = lane; bucket < bucket_count; bucket += workgroup_size)
    {
        histogram[radix_histogram_slot(block_idx, bucket, bucket_count)] = 0u;
    }
}

public void radix_histogram_add(
    uint block_idx,
    uint bucket,
    uint bucket_count,
    RWStructuredBuffer<uint> histogram)
{
    atomic_u32_add(
        histogram,
        radix_histogram_slot(block_idx, bucket, bucket_count),
        1u);
}

public void radix_u8_histogram_block<TSource: IRadixU8KeySource>(
    uint block_idx,
    uint lane,
    uint n_blocks,
    uint key_step,
    uint workgroup_size,
    uint bucket_count,
    RWStructuredBuffer<uint> histogram)
{
    if (block_idx >= n_blocks)
        return;

    clear_radix_histogram_block(
        lane,
        block_idx,
        bucket_count,
        workgroup_size,
        histogram);
    DeviceMemoryBarrierWithGroupSync();

    uint order_i = block_idx * workgroup_size + lane;
    if (order_i >= TSource.active_count())
        return;

    uint row = TSource.ordered_row(order_i);
    uint key = TSource.radix_key(row, key_step);
    radix_histogram_add(block_idx, key, bucket_count, histogram);
}

public uint radix_active_block_count(
    uint item_count,
    uint n_blocks,
    uint workgroup_size,
    uint max_blocks)
{
    uint blocks = (item_count + workgroup_size - 1u) / workgroup_size;
    return min(min(blocks, n_blocks), max_blocks);
}

public inline void radix_bucket_prefix_scan_4<
    let WG_SIZE: int,
    let SCAN_SLOTS: int>(
    uint lane,
    uint bucket,
    uint block_limit,
    uint bucket_count,
    StructuredBuffer<uint> radix_block_histogram,
    RWStructuredBuffer<uint> radix_block_bucket_prefix,
    RWStructuredBuffer<uint> radix_bucket_total,
    inout uint scan_values[SCAN_SLOTS])
{
    uint slot0 = lane;
    uint slot1 = lane + uint(WG_SIZE);
    uint slot2 = lane + uint(WG_SIZE) * 2u;
    uint slot3 = lane + uint(WG_SIZE) * 3u;
    uint value0 = slot0 < block_limit
                      ? radix_block_histogram[radix_histogram_slot(slot0, bucket, bucket_count)]
                      : 0u;
    uint value1 = slot1 < block_limit
                      ? radix_block_histogram[radix_histogram_slot(slot1, bucket, bucket_count)]
                      : 0u;
    uint value2 = slot2 < block_limit
                      ? radix_block_histogram[radix_histogram_slot(slot2, bucket, bucket_count)]
                      : 0u;
    uint value3 = slot3 < block_limit
                      ? radix_block_histogram[radix_histogram_slot(slot3, bucket, bucket_count)]
                      : 0u;
    uint inclusive0;
    uint inclusive1;
    uint inclusive2;
    uint inclusive3;

    prefix_scan_inclusive_4<uint, PrefixScanU32Add, WG_SIZE, SCAN_SLOTS>(
        lane,
        value0,
        value1,
        value2,
        value3,
        scan_values,
        inclusive0,
        inclusive1,
        inclusive2,
        inclusive3);

    if (slot0 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot0, bucket, bucket_count)] =
            inclusive0 - value0;
    if (slot1 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot1, bucket, bucket_count)] =
            inclusive1 - value1;
    if (slot2 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot2, bucket, bucket_count)] =
            inclusive2 - value2;
    if (slot3 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot3, bucket, bucket_count)] =
            inclusive3 - value3;

    if (lane == uint(WG_SIZE) - 1u)
        radix_bucket_total[bucket] = inclusive3;
}

public inline void radix_bucket_base_scan_2<
    let WG_SIZE: int,
    let SCAN_SLOTS: int>(
    uint lane,
    uint bucket_count,
    StructuredBuffer<uint> radix_bucket_total,
    RWStructuredBuffer<uint> radix_bucket_base,
    inout uint scan_values[SCAN_SLOTS])
{
    uint second = lane + uint(WG_SIZE);
    uint value0 = lane < bucket_count ? radix_bucket_total[lane] : 0u;
    uint value1 = second < bucket_count ? radix_bucket_total[second] : 0u;
    uint inclusive0;
    uint inclusive1;

    prefix_scan_inclusive_2<uint, PrefixScanU32Add, WG_SIZE, SCAN_SLOTS>(
        lane,
        value0,
        value1,
        scan_values,
        inclusive0,
        inclusive1);

    if (lane < bucket_count)
        radix_bucket_base[lane] = inclusive0 - value0;
    if (second < bucket_count)
        radix_bucket_base[second] = inclusive1 - value1;
}
