import reduce;

static const uint TEST_COUNT = 256u;
static const uint TREE_STRIDE = 128u;

StructuredBuffer<uint> values;
StructuredBuffer<uint> keys;
StructuredBuffer<uint> active_flags;

RWStructuredBuffer<uint> group_out;
RWStructuredBuffer<uint> tree_out;

groupshared uint reduce_u32_scratch[256];
groupshared uint2 reduce_u32x2_scratch[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint i = dtid.x;
    uint value = values[i];
    bool active = active_flags[i] != 0u;

    uint sum = group_reduce_power_of_two<uint, ReduceU32Add, 256>(
        lane,
        value,
        reduce_u32_scratch);
    uint max_value = group_reduce_power_of_two<uint, ReduceU32Max, 256>(
        lane,
        value,
        reduce_u32_scratch);
    uint min_value = group_reduce_power_of_two<uint, ReduceU32Min, 256>(
        lane,
        value,
        reduce_u32_scratch);
    uint active_sum = group_reduce_active_power_of_two<uint, ReduceU32Add, 256>(
        lane,
        value,
        active,
        reduce_u32_scratch);
    uint2 min_key_value = group_reduce_active_power_of_two<
        uint2,
        ReduceU32x2MinKeyValue,
        256>(
        lane,
        uint2(keys[i], value),
        active,
        reduce_u32x2_scratch);
    uint2 max_key_min_value = group_reduce_active_power_of_two<
        uint2,
        ReduceU32x2MaxKeyMinValue,
        256>(
        lane,
        uint2(keys[i], value),
        active,
        reduce_u32x2_scratch);

    if (i < TREE_STRIDE)
    {
        tree_out[i] = reduction_tree_step_value<uint, ReduceU32Add>(
            i,
            TREE_STRIDE,
            TEST_COUNT,
            values);
    }

    if (i == 0u)
    {
        group_out[0u] = sum;
        group_out[1u] = max_value;
        group_out[2u] = min_value;
        group_out[3u] = active_sum;
        group_out[4u] = min_key_value.x;
        group_out[5u] = min_key_value.y;
        group_out[6u] = max_key_min_value.x;
        group_out[7u] = max_key_min_value.y;
        group_out[8u] = reduction_tree_parent_count(255u);
        group_out[9u] = reduction_tree_parent_count(256u);
        group_out[10u] = reduction_tree_parent_count(257u);
        group_out[11u] = reduction_tree_has_right(17u, TREE_STRIDE, TEST_COUNT) ? 1u : 0u;
        group_out[12u] = reduction_tree_has_right(128u, TREE_STRIDE, TEST_COUNT) ? 1u : 0u;
    }
}
