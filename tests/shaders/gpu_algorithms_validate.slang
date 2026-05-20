import atomics;
import bitset;
import bit_packing;
import byte_packing;
import fixed_key;
import fixed_stack;
import gpu_index;
import intervals;
import linear_scan;
import prefix_scan;
import radix;
import range_query;
import scatter;
import segmented;
import sorted_join;
import status;

static const uint TEST_COUNT = 256u;
static const uint SORTED_COUNT = 64u;
static const uint QUERY_COUNT = 32u;
static const uint COMPACT_COUNT = 170u;
static const uint SCATTER_PAIR_BASE = TEST_COUNT + 1u;
static const uint SCATTER_RESERVATION_CAPACITY = 64u;
static const uint SCATTER_RESERVATION_BASE =
    SCATTER_PAIR_BASE + (COMPACT_COUNT + 1u) * 2u;
static const uint STABLE_BUCKET_COUNT = 8u;
static const uint INVALID = 0xffffffffu;

StructuredBuffer<uint> values;
StructuredBuffer<uint> segment_heads;
StructuredBuffer<uint> rank_keys;
StructuredBuffer<uint> key_steps;
StructuredBuffer<uint> sorted1;
StructuredBuffer<uint> query1;
StructuredBuffer<uint> flat_summary_in;
StructuredBuffer<uint> stable_bucket_base_in;
StructuredBuffer<uint> stable_block_bucket_prefix_in;

RWStructuredBuffer<uint> segmented_out;
RWStructuredBuffer<uint> rank_out;
RWStructuredBuffer<uint> radix_byte_out;
RWStructuredBuffer<uint> radix_field_out;
RWStructuredBuffer<uint> query1_begin_out;
RWStructuredBuffer<uint> query1_end_out;
RWStructuredBuffer<uint> query2_row_out;
RWStructuredBuffer<uint> query4_row_out;
RWStructuredBuffer<uint> scan_step_out;
RWStructuredBuffer<uint> scan_seed_out;
RWStructuredBuffer<uint> flat_summary_step_out;
RWStructuredBuffer<uint> flat_summary_seed_out;
RWStructuredBuffer<uint> scatter_store_out;
RWStructuredBuffer<uint> stable_scatter_out;
RWStructuredBuffer<uint> interval_out;

groupshared uint segmented_values[256];
groupshared uint segmented_heads[256];
groupshared uint rank_shared_keys[256];

public struct Query1Key
{
    uint value;
}

public struct Query1Compare : IRowQueryCompare<Query1Key>
{
    public static int compare(uint row, Query1Key key)
    {
        return compare_u32(sorted1[row], key.value);
    }
}

public struct Query2Key
{
    uint a;
    uint b;
}

uint sorted2_a_value(uint row)
{
    return row / 8u;
}

uint sorted2_b_value(uint row)
{
    return (row % 8u) * 2u;
}

uint query2_a_value(uint row)
{
    return (row * 3u) % 10u;
}

uint query2_b_value(uint row)
{
    return ((row * 5u) % 10u) * 2u;
}

public struct Query2FixedKey : IFixedU32RowKey<Query2Key>
{
    public static uint row_lane(uint row, uint lane)
    {
        return lane == 0u ? sorted2_a_value(row) : sorted2_b_value(row);
    }

    public static uint key_lane(Query2Key key, uint lane)
    {
        return lane == 0u ? key.a : key.b;
    }
}

public struct Query2GenericCompare : IRowQueryCompare<Query2Key>
{
    public static int compare(uint row, Query2Key key)
    {
        return fixed_u32_row_key_compare<Query2Key, Query2FixedKey>(
            row,
            key,
            2u);
    }
}

public struct Query2LeftKey : ISortedJoinLeftKey<Query2Key>
{
    public static bool make_key(uint left_row, out Query2Key key)
    {
        key.a = 0u;
        key.b = 0u;
        if (left_row >= QUERY_COUNT)
            return false;
        key.a = query2_a_value(left_row);
        key.b = query2_b_value(left_row);
        return true;
    }
}

public struct Query4Key
{
    uint a;
    uint b;
    uint c;
    uint d;
}

uint sorted4_a_value(uint row)
{
    return row / 16u;
}

uint sorted4_b_value(uint row)
{
    return (row / 8u) % 2u;
}

uint sorted4_c_value(uint row)
{
    return (row / 4u) % 2u;
}

uint sorted4_d_value(uint row)
{
    return row % 4u;
}

uint query4_a_value(uint row)
{
    return (row * 3u) % 5u;
}

uint query4_b_value(uint row)
{
    return (row * 5u) % 3u;
}

uint query4_c_value(uint row)
{
    return (row * 7u) % 3u;
}

uint query4_d_value(uint row)
{
    return (row * 11u) % 6u;
}

public struct Query4FixedKey : IFixedU32RowKey<Query4Key>
{
    public static uint row_lane(uint row, uint lane)
    {
        if (lane == 0u)
            return sorted4_a_value(row);
        if (lane == 1u)
            return sorted4_b_value(row);
        if (lane == 2u)
            return sorted4_c_value(row);
        return sorted4_d_value(row);
    }

    public static uint key_lane(Query4Key key, uint lane)
    {
        if (lane == 0u)
            return key.a;
        if (lane == 1u)
            return key.b;
        if (lane == 2u)
            return key.c;
        return key.d;
    }
}

public struct Query4GenericCompare : IRowQueryCompare<Query4Key>
{
    public static int compare(uint row, Query4Key key)
    {
        return fixed_u32_row_key_compare<Query4Key, Query4FixedKey>(
            row,
            key,
            4u);
    }
}

public struct Query4RowValue : ISortedJoinValue<uint>
{
    public static uint invalid_value()
    {
        return INVALID;
    }

    public static uint row_value(uint row)
    {
        return row;
    }
}

public struct ScatterPair
{
    uint a;
    uint b;
}

public struct ScatterPairSink : IScatterSink<ScatterPair>
{
    public static void store(uint dst, ScatterPair value)
    {
        uint base = SCATTER_PAIR_BASE + dst * 2u;
        scatter_store_out[base + 0u] = value.a;
        scatter_store_out[base + 1u] = value.b;
    }
}

public struct StableScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count()
    {
        return TEST_COUNT;
    }

    public static uint inactive_value()
    {
        return 0u;
    }

    public static uint ordered_value(uint order_i)
    {
        return values[order_i];
    }

    public static uint radix_key(uint value, uint key_step)
    {
        return value & (STABLE_BUCKET_COUNT - 1u);
    }
}

public struct StableScatterSink : IScatterSink<uint>
{
    public static void store(uint dst, uint value)
    {
        stable_scatter_out[dst] = value;
    }
}

public struct SegmentScatterValidationContext
{
    uint add;
}

public struct SegmentScatterValidationEmitter :
    ISegmentScatterEmitter<SegmentScatterValidationContext>
{
    public static bool keep(uint row)
    {
        return row < 12u && row % 3u != 0u;
    }

    public static void store(
        uint dst,
        uint row,
        uint local_i,
        SegmentScatterValidationContext context)
    {
        interval_out[dst] = context.add + row + local_i * 100u;
    }
}

uint compact_pair_flag(uint i)
{
    return i % 3u == 0u ? 0u : 1u;
}

uint compact_pair_prefix(uint i)
{
    return i - ((i + 2u) / 3u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint i = dtid.x;
    uint value = i < TEST_COUNT ? values[i] : 0u;
    uint head = i < TEST_COUNT ? segment_heads[i] : 1u;
    uint segmented = segmented_scan_inclusive<uint, PrefixScanU32Add, 256>(
        lane,
        value,
        head,
        segmented_values,
        segmented_heads);

    uint rank_key = i < TEST_COUNT ? rank_keys[i] : SCATTER_INACTIVE_KEY;
    uint rank = local_same_key_rank<uint, ScatterU32KeyEquality, 256>(
        lane,
        rank_key,
        rank_shared_keys);

    if (i < TEST_COUNT)
    {
        segmented_out[i] = segmented;
        rank_out[i] = rank;
        radix_byte_out[i] = radix_byte_key(values[i], key_steps[i]);
        radix_field_out[i] = radix_field_index(key_steps[i], 3u);
        scan_step_out[i] = parallel_scan_step_value<uint, PrefixScanU32Add>(
            i,
            7u,
            key_steps[i],
            values);
        scan_seed_out[i] = parallel_scan_step_value<uint, PrefixScanU32Add>(
            i,
            0u,
            key_steps[i],
            values);
        scatter_store<uint>(
            scatter_store_out,
            i,
            TEST_COUNT,
            values[i] + 17u);
        if (i == 0u)
        {
            bool rejected = !scatter_store<uint>(
                scatter_store_out,
                TEST_COUNT + 1u,
                TEST_COUNT,
                123u);
            scatter_store_out[TEST_COUNT] = rejected ? 0u : 1u;

            ScatterPair rejected_pair;
            rejected_pair.a = 1u;
            rejected_pair.b = 1u;
            CompactScatterSlot rejected_slot = compact_scatter_slot(
                1u,
                COMPACT_COUNT + 1u);
            bool pair_rejected = !compact_scatter_emit<
                ScatterPair,
                ScatterPairSink>(
                    rejected_slot,
                    COMPACT_COUNT,
                    rejected_pair);
            uint rejected_base = SCATTER_PAIR_BASE + COMPACT_COUNT * 2u;
            scatter_store_out[rejected_base + 0u] = pair_rejected ? 0u : 1u;
            scatter_store_out[rejected_base + 1u] = pair_rejected ? 0u : 1u;
        }

        ScatterPair pair;
        pair.a = values[i] + 101u;
        pair.b = (values[i] * 3u) + i;
        CompactScatterSlot pair_slot = compact_scatter_slot(
            compact_pair_flag(i),
            compact_pair_prefix(i));
        compact_scatter_emit<ScatterPair, ScatterPairSink>(
            pair_slot,
            COMPACT_COUNT,
            pair);

        uint reserved_slot;
        if (reserve_counter_slot(
                scatter_store_out,
                SCATTER_RESERVATION_BASE,
                SCATTER_RESERVATION_CAPACITY,
                reserved_slot))
        {
            scatter_store_out[SCATTER_RESERVATION_BASE + 1u + reserved_slot] = 1u;
        }

        uint4 summary_seed = uint4(
            i + 1u,
            (i * 2u) + 3u,
            (i * 5u) % 31u,
            0xffffffffu - ((i * 13u) % 1024u));
        store_u32x4_flat(
            flat_summary_step_out,
            i * 4u,
            parallel_scan_step_u32x4_flat<PrefixScanU32x4SumSumMaxMin>(
                i,
                5u,
                summary_seed,
                flat_summary_in,
                4u));
        store_u32x4_flat(
            flat_summary_seed_out,
            i * 4u,
            parallel_scan_step_u32x4_flat<PrefixScanU32x4SumSumMaxMin>(
                i,
                0u,
                summary_seed,
                flat_summary_in,
                4u));
    }

    stable_radix_scatter_block<uint, StableScatterSource, StableScatterSink, 256>(
        0u,
        lane,
        1u,
        0u,
        STABLE_BUCKET_COUNT,
        stable_bucket_base_in,
        stable_block_bucket_prefix_in,
        rank_shared_keys);

    if (i == 0u)
    {
        U32Interval a = interval_u32(3u, 11u);
        U32Interval b = interval_u32(10u, 18u);
        U32Interval c = interval_u32(12u, 20u);
        U32Interval invalid_interval = interval_u32(INVALID, 4u);
        U32Interval extended = interval_u32_extend_end(a, 17u);
        interval_out[0u] = interval_u32_valid(a, INVALID) ? 1u : 0u;
        interval_out[1u] = interval_u32_overlaps(a, b, INVALID) ? 1u : 0u;
        interval_out[2u] = interval_u32_overlaps(a, c, INVALID) ? 1u : 0u;
        interval_out[3u] = interval_u32_contains_point(a, 3u, INVALID) ? 1u : 0u;
        interval_out[4u] = interval_u32_strictly_contains_point(a, 3u, INVALID) ? 1u : 0u;
        interval_out[5u] = interval_u32_strictly_contains_point(a, 10u, INVALID) ? 1u : 0u;
        interval_out[6u] = interval_u32_valid(invalid_interval, INVALID) ? 1u : 0u;
        interval_out[7u] = extended.end;
        uint packed = pack_u16_pair(0x12345u, 0xabcdu);
        interval_out[8u] = unpack_u16_pair_low(packed);
        interval_out[9u] = unpack_u16_pair_high(packed);
        uint mask = bitset32_insert(bitset32_insert(0u, 3u), 9u);
        uint other_mask = bitset32_union(bitset32_single(9u), bitset32_single(31u));
        interval_out[10u] = bitset32_contains(mask, 3u) ? 1u : 0u;
        interval_out[11u] = bitset32_contains(bitset32_remove(mask, 3u), 3u) ? 1u : 0u;
        interval_out[12u] = bitset32_intersects(mask, other_mask) ? 1u : 0u;
        interval_out[13u] = bitset32_count(bitset32_union(mask, other_mask));
        StageStatus4 fallback_status = make_stage_status4_from_result(
            false,
            77u,
            0xffffffffu,
            12u,
            0u,
            44u,
            99u,
            5u);
        StageStatus4 propagated_status = make_stage_status4_from_result(
            false,
            77u,
            0xffffffffu,
            12u,
            31u,
            44u,
            99u,
            5u);
        interval_out[14u] = bitset32_prefix(5u);
        interval_out[15u] = bitset32_full_below(mask, 4u) ? 1u : 0u;
        interval_out[16u] = bitset32_contains_all(other_mask, bitset32_single(31u)) ? 1u : 0u;
        interval_out[17u] = bitset32_first_set(mask, INVALID);
        interval_out[18u] = bitset32_first_clear_below(mask, 5u, INVALID);
        interval_out[19u] = fallback_status.error;
        interval_out[20u] = fallback_status.detail;
        interval_out[21u] = propagated_status.error;
        interval_out[22u] = propagated_status.detail;
        interval_out[23u] = linear_dispatch_thread_id_2d(uint3(7u, 3u, 0u), 100u);
        interval_out[24u] = u32_le_byte(0xa1b2c3d4u, 0u);
        interval_out[25u] = u32_le_byte(0xa1b2c3d4u, 3u);
        interval_out[26u] = pack_u8x4(0x11u, 0x22u, 0x33u, 0x44u);
        interval_out[27u] = replace_packed_u8(0x44332211u, 2u, 0xaau);
        interval_out[28u] = packed_u8_word_from_unpacked(values, 0u, TEST_COUNT);
        interval_out[29u] = u8_masked(0x1ffu);
        interval_out[30u] = bit_mask_u32(5u);
        interval_out[31u] = bitfield_extract_u32(0xf0u, 4u, 4u);
        interval_out[32u] = bitfield_insert_u32(0xffff0000u, 4u, 4u, 0x5u);
        interval_out[33u] = pack_u2x4(0u, 1u, 2u, 3u);
        interval_out[34u] = packed_u2_at(0xe4u, 2u);
        interval_out[35u] = pack_u2x4_at_offset(8u, 0u, 1u, 2u, 3u);
        interval_out[36u] = packed_u2_at_offset(0xe400u, 8u, 3u);
        write_stage_status4_at(
            interval_out,
            37u,
            make_stage_status4(9u, 0u, 77u, 5u));
        interval_out[43u] = INVALID;
        publish_stage_error_min_detail4_at(interval_out, 41u, 123u, 22u);
        interval_out[46u] = INVALID;
        publish_stage_error_min_detail_extra4_at(interval_out, 44u, 321u, 19u, 88u);
        publish_stage_error_first4_at(interval_out, 48u, 654u, 33u, 77u);
        write_stage_status4_at(
            interval_out,
            52u,
            make_stage_status4(1u, 0u, 9u, 4u));
        interval_out[56u] = increment_stage_count4_at(interval_out, 52u, 7u);
        interval_out[57u] = 3u;
        interval_out[58u] = atomic_u32_add(interval_out, 57u, 4u);
        interval_out[59u] = interval_out[57u];
        interval_out[60u] = 9u;
        interval_out[61u] = atomic_u32_min(interval_out, 60u, 5u);
        interval_out[62u] = interval_out[60u];
        interval_out[63u] = 2u;
        interval_out[64u] = atomic_u32_max(interval_out, 63u, 8u);
        interval_out[65u] = interval_out[63u];
        interval_out[66u] = 11u;
        interval_out[67u] = atomic_u32_compare_exchange(interval_out, 66u, 11u, 12u);
        interval_out[68u] = interval_out[66u];
        interval_out[69u] = 0xfu;
        interval_out[70u] = atomic_u32_and(interval_out, 69u, 0x3u);
        interval_out[71u] = interval_out[69u];
        interval_out[72u] = 0x8u;
        interval_out[73u] = atomic_u32_or(interval_out, 72u, 0x3u);
        interval_out[74u] = interval_out[72u];
        interval_out[75u] = valid_index_or_invalid(3u, 8u, INVALID) ? 1u : 0u;
        interval_out[76u] = valid_index_or_invalid(INVALID, 8u, INVALID) ? 1u : 0u;
        interval_out[77u] = valid_index_or_invalid(8u, 8u, INVALID) ? 1u : 0u;
        interval_out[78u] = active_count_from_rw_status(interval_out[37u], interval_out, 40u);
        uint4 invalid4 = uint4_fill(INVALID);
        uint4 mixed4 = uint4(INVALID, 2u, INVALID, INVALID);
        interval_out[79u] = uint4_all_equal(invalid4, INVALID) ? 1u : 0u;
        interval_out[80u] = uint4_any_not_equal(invalid4, INVALID) ? 1u : 0u;
        interval_out[81u] = uint4_any_not_equal(mixed4, INVALID) ? 1u : 0u;
        StageStatus4 first_failed = make_stage_status4(0u, 41u, 42u, 0u);
        StageStatus4 second_failed = make_stage_status4(0u, 51u, 52u, 0u);
        StageStatus4 second_missing_error = make_stage_status4(0u, 0u, 61u, 0u);
        StageStatus4 selected_first = make_stage_status4_from_upstream2(
            false,
            90u,
            INVALID,
            0u,
            false,
            first_failed,
            second_failed,
            100u,
            200u);
        StageStatus4 selected_second = make_stage_status4_from_upstream2(
            false,
            90u,
            INVALID,
            0u,
            true,
            first_failed,
            second_failed,
            100u,
            200u);
        StageStatus4 selected_fallback = make_stage_status4_from_upstream2(
            false,
            90u,
            INVALID,
            0u,
            true,
            first_failed,
            second_missing_error,
            100u,
            200u);
        StageStatus4 selected_success = make_stage_status4_from_upstream2(
            true,
            90u,
            7u,
            8u,
            true,
            first_failed,
            second_failed,
            100u,
            200u);
        StageStatus4 single_failed = make_stage_status4_from_upstream1(
            false,
            91u,
            7u,
            9u,
            first_failed,
            100u,
            200u);
        StageStatus4 single_fallback = make_stage_status4_from_upstream1(
            false,
            91u,
            7u,
            9u,
            second_missing_error,
            100u,
            200u);
        StageStatus4 single_success = make_stage_status4_from_upstream1(
            true,
            91u,
            7u,
            9u,
            first_failed,
            100u,
            200u);
        interval_out[82u] = selected_first.error + selected_first.detail;
        interval_out[83u] = selected_second.error + selected_second.detail;
        interval_out[84u] = selected_fallback.error + selected_fallback.detail;
        interval_out[85u] = selected_success.ok + selected_success.count;
        interval_out[86u] = single_failed.error + single_failed.detail;
        interval_out[87u] = single_fallback.error + single_fallback.detail;
        interval_out[88u] = single_success.ok + single_success.count;
        SegmentScatterValidationContext segment_context;
        segment_context.add = 10u;
        SegmentScatterResult segment_result = scatter_segment_rows_if<
            SegmentScatterValidationContext,
            SegmentScatterValidationEmitter>(
            0u,
            12u,
            89u,
            95u,
            segment_context,
            INVALID);
        interval_out[95u] = segment_result.matched;
        interval_out[96u] = segment_result.stored;
        interval_out[97u] = segment_result.first_oob_dst;
        interval_out[98u] = row_major_slot(7u, 6u, 4u);
        interval_out[99u] = row_major_column_in_bounds(6u, 6u) ? 1u : 0u;
        interval_out[100u] = row_major_slot_in_bounds(7u, 6u, 4u, 64u) ? 1u : 0u;
        uint active_end[4];
        linear_scan_active_clear<4>(active_end, INVALID);
        interval_out[101u] = linear_scan_first_available_rank<4>(
            10u,
            3u,
            active_end,
            INVALID);
        linear_scan_activate_rank<4>(2u, 15u, active_end);
        interval_out[102u] = linear_scan_first_available_rank<4>(
            12u,
            0u,
            active_end,
            INVALID);
        interval_out[103u] = linear_scan_first_available_rank<4>(
            16u,
            0u,
            active_end,
            INVALID);
        uint4 stack_values[3];
        uint stack_top = 0u;
        fixed_stack_push<uint4, 3>(stack_top, stack_values, uint4(1u, 2u, 3u, 4u));
        fixed_stack_push<uint4, 3>(stack_top, stack_values, uint4(5u, 6u, 7u, 8u));
        uint4 stack_peek = fixed_stack_peek_or<uint4, 3>(
            stack_top,
            stack_values,
            uint4(INVALID, INVALID, INVALID, INVALID));
        interval_out[104u] = stack_peek.x + stack_top * 10u;
        uint4 popped_stack_value;
        interval_out[105u] = fixed_stack_pop<uint4, 3>(
            stack_top,
            stack_values,
            popped_stack_value,
            uint4(INVALID, INVALID, INVALID, INVALID)) ? popped_stack_value.y : 0u;
        interval_out[106u] = stack_top;
        interval_out[107u] = fixed_stack_full<3>(stack_top) ? 1u : 0u;
        fixed_stack_push<uint4, 3>(stack_top, stack_values, uint4(9u, 10u, 11u, 12u));
        fixed_stack_push<uint4, 3>(stack_top, stack_values, uint4(13u, 14u, 15u, 16u));
        interval_out[108u] = fixed_stack_full<3>(stack_top) ? 1u : 0u;
        interval_out[109u] = !fixed_stack_push<uint4, 3>(
            stack_top,
            stack_values,
            uint4(17u, 18u, 19u, 20u)) ? 1u : 0u;
        Query2Key fixed_key_equal;
        fixed_key_equal.a = 0u;
        fixed_key_equal.b = 8u;
        Query2Key fixed_key_before;
        fixed_key_before.a = 0u;
        fixed_key_before.b = 7u;
        int fixed_cmp = fixed_u32_row_key_compare<Query2Key, Query2FixedKey>(
            4u,
            fixed_key_before,
            2u);
        interval_out[110u] = fixed_u32_row_key_equal<Query2Key, Query2FixedKey>(
            4u,
            fixed_key_equal,
            2u) ? 1u : 0u;
        interval_out[111u] = fixed_cmp < 0 ? 0u : (fixed_cmp > 0 ? 2u : 1u);
        interval_out[112u] = fixed_key_encode_nullable_u32(41u, INVALID);
        interval_out[113u] = fixed_key_encode_nullable_u32(INVALID, INVALID);
        bool row_store_ok = row_major_store<uint>(
            interval_out,
            19u,
            6u,
            0u,
            700u);
        bool row_store_rejected = !row_major_store<uint>(
            interval_out,
            19u,
            6u,
            6u,
            701u);
        interval_out[115u] = row_store_ok ? 1u : 0u;
        interval_out[116u] = row_store_rejected ? 1u : 0u;
        interval_out[117u] = row_major_load<uint>(
            values,
            3u,
            8u,
            5u,
            777u);
        interval_out[118u] = row_major_load<uint>(
            values,
            3u,
            8u,
            8u,
            777u);
        interval_out[119u] = row_major_load_rw<uint>(
            interval_out,
            19u,
            6u,
            0u,
            778u);
        interval_out[120u] = row_major_load_rw<uint>(
            interval_out,
            19u,
            6u,
            6u,
            778u);
    }

    if (i < QUERY_COUNT)
    {
        Query1Key key1;
        key1.value = query1[i];
        QueryRange range = equal_range_query<Query1Key, Query1Compare>(
            SORTED_COUNT,
            key1);
        query1_begin_out[i] = range.begin;
        query1_end_out[i] = range.end;
        uint query2_row;
        query2_row_out[i] = sorted_join_find_left_row<
            Query2Key,
            Query2LeftKey,
            Query2GenericCompare>(
            i,
            SORTED_COUNT,
            INVALID,
            query2_row)
            ? query2_row
            : INVALID;

        Query4Key key4;
        key4.a = query4_a_value(i);
        key4.b = query4_b_value(i);
        key4.c = query4_c_value(i);
        key4.d = query4_d_value(i);
        query4_row_out[i] = sorted_join_project_key_or_invalid<
            Query4Key,
            uint,
            Query4GenericCompare,
            Query4RowValue>(
            SORTED_COUNT,
            key4,
            INVALID);
    }
}
