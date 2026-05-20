import prefix_scan;
import segmented;

static const uint TEST_COUNT = 256u;

StructuredBuffer<uint> values;
StructuredBuffer<uint> segment_heads;
StructuredBuffer<uint> active_flags;

RWStructuredBuffer<uint> inclusive_out;
RWStructuredBuffer<uint> exclusive_out;
RWStructuredBuffer<uint> direct_exclusive_out;
RWStructuredBuffer<uint> active_inclusive_out;
RWStructuredBuffer<uint> active_exclusive_out;
RWStructuredBuffer<uint> tail_total_out;
RWStructuredBuffer<uint> tail_flag_out;
RWStructuredBuffer<uint> inactive_tail_flag_out;
RWStructuredBuffer<uint> pair_prefix_out;

groupshared uint value_scratch[256];
groupshared uint value_heads[256];
groupshared uint direct_scratch[256];
groupshared uint direct_heads[256];
groupshared uint active_scratch[256];
groupshared uint active_heads[256];
groupshared uint2 pair_scratch[256];
groupshared uint pair_heads[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint i = dtid.x;
    uint head = segment_head_flag(segment_heads[i] != 0u);
    uint value = values[i];

    uint inclusive;
    uint exclusive;
    segmented_scan_prefixes<uint, PrefixScanU32Add, 256>(
        lane,
        value,
        head,
        value_scratch,
        value_heads,
        inclusive,
        exclusive);

    uint direct_exclusive = segmented_scan_exclusive<uint, PrefixScanU32Add, 256>(
        lane,
        value,
        head,
        direct_scratch,
        direct_heads);

    uint active_inclusive;
    uint active_exclusive;
    segmented_scan_prefixes<uint, PrefixScanU32Add, 256>(
        lane,
        active_flags[i] != 0u ? 1u : 0u,
        head,
        active_scratch,
        active_heads,
        active_inclusive,
        active_exclusive);

    uint2 pair_inclusive;
    uint2 pair_exclusive;
    segmented_scan_prefixes<uint2, PrefixScanU32x2Add, 256>(
        lane,
        uint2(value, value * 3u + active_flags[i]),
        head,
        pair_scratch,
        pair_heads,
        pair_inclusive,
        pair_exclusive);

    uint next_head = i + 1u < TEST_COUNT ? segment_heads[i + 1u] : 1u;
    bool tail = segment_is_tail(lane, TEST_COUNT, next_head);
    bool inactive_tail = segment_is_tail(lane, TEST_COUNT - 17u, next_head);

    inclusive_out[i] = inclusive;
    exclusive_out[i] = exclusive;
    direct_exclusive_out[i] = direct_exclusive;
    active_inclusive_out[i] = active_inclusive;
    active_exclusive_out[i] = active_exclusive;
    tail_total_out[i] = segment_total_or_identity<uint, PrefixScanU32Add>(tail, inclusive);
    tail_flag_out[i] = tail ? 1u : 0u;
    inactive_tail_flag_out[i] = inactive_tail ? 1u : 0u;

    uint pair_base = i * 4u;
    pair_prefix_out[pair_base + 0u] = pair_inclusive.x;
    pair_prefix_out[pair_base + 1u] = pair_inclusive.y;
    pair_prefix_out[pair_base + 2u] = pair_exclusive.x;
    pair_prefix_out[pair_base + 3u] = pair_exclusive.y;
}
