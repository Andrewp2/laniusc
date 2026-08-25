import atomics;
import byte_packing;
import prefix_scan;

/// Number of globally materialized buckets for one byte digit. Inactive lanes
/// use a 257th key only inside the workgroup-local stable scatter; they never
/// contribute to the global histogram or prefix tables.
public static const uint RADIX_U8_BUCKETS = 256u;

public interface IRadixU8KeySource
{
    static uint active_count();
    static uint ordered_row(uint order_i);
    static uint radix_key(uint row, uint key_step);
}

public uint radix_byte_key(uint value, uint key_step)
{
    return packed_u8_at(value, key_step);
}

/// Extracts one byte from two variable-width fields packed as
/// `field1:field0`, without requiring 64-bit shader arithmetic. The first
/// field is the least-significant stable-sort field. Bits outside each
/// declared width are ignored, including the unused bits of the final byte.
public uint radix_packed_u32x2_variable_bit_key(
    uint field0,
    uint field1,
    uint field0_bits,
    uint field1_bits,
    uint key_step)
{
    uint bits0 = min(field0_bits, 32u);
    uint bits1 = min(field1_bits, 32u);
    uint bit_offset = key_step * 8u;
    uint result = 0u;
    uint result_bits = 0u;

    if (bit_offset < bits0)
    {
        uint take = min(8u, bits0 - bit_offset);
        uint mask = (1u << take) - 1u;
        result = (field0 >> bit_offset) & mask;
        result_bits = take;
        bit_offset = 0u;
    }
    else
        bit_offset -= bits0;

    if (result_bits < 8u && bit_offset < bits1)
    {
        uint take = min(8u - result_bits, bits1 - bit_offset);
        uint mask = (1u << take) - 1u;
        result |= ((field1 >> bit_offset) & mask) << result_bits;
    }
    return result;
}

/// Equal-width convenience wrapper retained for existing key projections.
public uint radix_packed_u32x2_bit_key(
    uint field0,
    uint field1,
    uint bits_per_field,
    uint key_step)
{
    uint bits = clamp(bits_per_field, 1u, 32u);
    return radix_packed_u32x2_variable_bit_key(
        field0, field1, bits, bits, key_step);
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
    // One lane clears one global u8 bucket. Keep the strided form generic for
    // callers whose workgroup size differs from the bucket count.
    uint bucket0 = lane;
    if (bucket0 < bucket_count)
        histogram[radix_histogram_slot(block_idx, bucket0, bucket_count)] = 0u;

    uint bucket1 = lane + workgroup_size;
    if (bucket1 < bucket_count)
        histogram[radix_histogram_slot(block_idx, bucket1, bucket_count)] = 0u;
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
    uint workgroup_size)
{
    uint blocks = item_count / workgroup_size;
    if (item_count % workgroup_size != 0u)
        blocks += 1u;
    return min(blocks, n_blocks);
}

/// Computes an exclusive prefix over the histogram blocks for one bucket.
/// Each lane owns one contiguous range, scans it locally, and then the
/// workgroup scans the 256 lane totals. Unlike the old fully materialized
/// 4096-slot scan, this remains correct for every GPU-dispatchable row count
/// while using only one workgroup-sized shared array.
public void radix_bucket_prefix_scan<let WG_SIZE: int>(
    uint lane,
    uint bucket,
    uint block_limit,
    uint bucket_count,
    StructuredBuffer<uint> radix_block_histogram,
    RWStructuredBuffer<uint> radix_block_bucket_prefix,
    RWStructuredBuffer<uint> radix_bucket_total,
    inout uint lane_totals[WG_SIZE])
{
    uint items_per_lane = block_limit / uint(WG_SIZE);
    if (block_limit % uint(WG_SIZE) != 0u)
        items_per_lane += 1u;
    uint begin = lane * items_per_lane;
    uint end = min(begin + items_per_lane, block_limit);
    uint local_total = 0u;
    for (uint block = begin; block < end; ++block)
    {
        uint slot = radix_histogram_slot(block, bucket, bucket_count);
        radix_block_bucket_prefix[slot] = local_total;
        local_total += radix_block_histogram[slot];
    }

    uint inclusive_lane_total = prefix_scan_inclusive<
        uint, PrefixScanU32Add, WG_SIZE>(
            lane, local_total, lane_totals);
    uint lane_base = inclusive_lane_total - local_total;
    for (uint block = begin; block < end; ++block)
    {
        uint slot = radix_histogram_slot(block, bucket, bucket_count);
        radix_block_bucket_prefix[slot] += lane_base;
    }

    if (lane == uint(WG_SIZE) - 1u)
        radix_bucket_total[bucket] = inclusive_lane_total;
}
