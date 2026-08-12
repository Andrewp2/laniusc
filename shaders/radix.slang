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

/// Extracts one byte from two equal-width fields packed as
/// `field1:field0`, without requiring 64-bit shader arithmetic. The first
/// field is the least-significant stable-sort field.
public uint radix_packed_u32x2_bit_key(
    uint field0,
    uint field1,
    uint bits_per_field,
    uint key_step)
{
    uint bits = clamp(bits_per_field, 1u, 32u);
    uint bit_offset = key_step * 8u;
    if (bit_offset < bits)
    {
        uint remaining = bits - bit_offset;
        uint low = field0 >> bit_offset;
        if (remaining >= 8u)
            return low & 0xffu;

        uint low_mask = (1u << remaining) - 1u;
        return (low & low_mask) | ((field1 << remaining) & 0xffu);
    }

    return (field1 >> (bit_offset - bits)) & 0xffu;
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
    uint workgroup_size,
    uint max_blocks)
{
    uint blocks = (item_count + workgroup_size - 1u) / workgroup_size;
    return min(min(blocks, n_blocks), max_blocks);
}

public void radix_bucket_prefix_scan_16<
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
    uint slot4 = lane + uint(WG_SIZE) * 4u;
    uint slot5 = lane + uint(WG_SIZE) * 5u;
    uint slot6 = lane + uint(WG_SIZE) * 6u;
    uint slot7 = lane + uint(WG_SIZE) * 7u;
    uint slot8 = lane + uint(WG_SIZE) * 8u;
    uint slot9 = lane + uint(WG_SIZE) * 9u;
    uint slot10 = lane + uint(WG_SIZE) * 10u;
    uint slot11 = lane + uint(WG_SIZE) * 11u;
    uint slot12 = lane + uint(WG_SIZE) * 12u;
    uint slot13 = lane + uint(WG_SIZE) * 13u;
    uint slot14 = lane + uint(WG_SIZE) * 14u;
    uint slot15 = lane + uint(WG_SIZE) * 15u;
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
    uint value4 = slot4 < block_limit
                      ? radix_block_histogram[radix_histogram_slot(slot4, bucket, bucket_count)]
                      : 0u;
    uint value5 = slot5 < block_limit
                      ? radix_block_histogram[radix_histogram_slot(slot5, bucket, bucket_count)]
                      : 0u;
    uint value6 = slot6 < block_limit
                      ? radix_block_histogram[radix_histogram_slot(slot6, bucket, bucket_count)]
                      : 0u;
    uint value7 = slot7 < block_limit
                      ? radix_block_histogram[radix_histogram_slot(slot7, bucket, bucket_count)]
                      : 0u;
    uint value8 = slot8 < block_limit
                      ? radix_block_histogram[radix_histogram_slot(slot8, bucket, bucket_count)]
                      : 0u;
    uint value9 = slot9 < block_limit
                      ? radix_block_histogram[radix_histogram_slot(slot9, bucket, bucket_count)]
                      : 0u;
    uint value10 = slot10 < block_limit
                       ? radix_block_histogram[radix_histogram_slot(slot10, bucket, bucket_count)]
                       : 0u;
    uint value11 = slot11 < block_limit
                       ? radix_block_histogram[radix_histogram_slot(slot11, bucket, bucket_count)]
                       : 0u;
    uint value12 = slot12 < block_limit
                       ? radix_block_histogram[radix_histogram_slot(slot12, bucket, bucket_count)]
                       : 0u;
    uint value13 = slot13 < block_limit
                       ? radix_block_histogram[radix_histogram_slot(slot13, bucket, bucket_count)]
                       : 0u;
    uint value14 = slot14 < block_limit
                       ? radix_block_histogram[radix_histogram_slot(slot14, bucket, bucket_count)]
                       : 0u;
    uint value15 = slot15 < block_limit
                       ? radix_block_histogram[radix_histogram_slot(slot15, bucket, bucket_count)]
                       : 0u;
    uint inclusive0;
    uint inclusive1;
    uint inclusive2;
    uint inclusive3;
    uint inclusive4;
    uint inclusive5;
    uint inclusive6;
    uint inclusive7;
    uint inclusive8;
    uint inclusive9;
    uint inclusive10;
    uint inclusive11;
    uint inclusive12;
    uint inclusive13;
    uint inclusive14;
    uint inclusive15;

    prefix_scan_inclusive_16<uint, PrefixScanU32Add, WG_SIZE, SCAN_SLOTS>(
        lane,
        value0,
        value1,
        value2,
        value3,
        value4,
        value5,
        value6,
        value7,
        value8,
        value9,
        value10,
        value11,
        value12,
        value13,
        value14,
        value15,
        scan_values,
        inclusive0,
        inclusive1,
        inclusive2,
        inclusive3,
        inclusive4,
        inclusive5,
        inclusive6,
        inclusive7,
        inclusive8,
        inclusive9,
        inclusive10,
        inclusive11,
        inclusive12,
        inclusive13,
        inclusive14,
        inclusive15);

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
    if (slot4 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot4, bucket, bucket_count)] =
            inclusive4 - value4;
    if (slot5 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot5, bucket, bucket_count)] =
            inclusive5 - value5;
    if (slot6 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot6, bucket, bucket_count)] =
            inclusive6 - value6;
    if (slot7 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot7, bucket, bucket_count)] =
            inclusive7 - value7;
    if (slot8 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot8, bucket, bucket_count)] =
            inclusive8 - value8;
    if (slot9 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot9, bucket, bucket_count)] =
            inclusive9 - value9;
    if (slot10 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot10, bucket, bucket_count)] =
            inclusive10 - value10;
    if (slot11 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot11, bucket, bucket_count)] =
            inclusive11 - value11;
    if (slot12 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot12, bucket, bucket_count)] =
            inclusive12 - value12;
    if (slot13 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot13, bucket, bucket_count)] =
            inclusive13 - value13;
    if (slot14 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot14, bucket, bucket_count)] =
            inclusive14 - value14;
    if (slot15 < block_limit)
        radix_block_bucket_prefix[radix_histogram_slot(slot15, bucket, bucket_count)] =
            inclusive15 - value15;

    if (lane == uint(WG_SIZE) - 1u)
        radix_bucket_total[bucket] = inclusive15;
}
