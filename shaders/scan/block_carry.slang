// The carry of one block of a counted exclusive scan, read straight from
// the per-block sums the local pass wrote: the sum of the `limit` blocks
// before it. Every workgroup of the apply pass computes its own carry, so
// no pass scans the block sums and no workgroup reads another workgroup's
// writes of the same dispatch. A workgroup reads `limit` sums (strided over
// its 256 lanes) and reduces them in groupshared memory; every lane must
// call it.

groupshared uint block_carry_values[256];
groupshared uint2 block_carry_values2[256];

public uint block_carry_sum(uint lane, uint limit, StructuredBuffer<uint> block_sum)
{
    uint sum = 0u;
    for (uint block = lane; block < limit; block += 256u)
        sum += block_sum[block];
    block_carry_values[lane] = sum;
    GroupMemoryBarrierWithGroupSync();
    for (uint width = 128u; width != 0u; width >>= 1u)
    {
        if (lane < width)
            block_carry_values[lane] += block_carry_values[lane + width];
        GroupMemoryBarrierWithGroupSync();
    }
    return block_carry_values[0];
}

public uint2 block_carry_sum2(
    uint lane,
    uint limit,
    StructuredBuffer<uint> block_sum_left,
    StructuredBuffer<uint> block_sum_right)
{
    uint2 sum = uint2(0u, 0u);
    for (uint block = lane; block < limit; block += 256u)
        sum += uint2(block_sum_left[block], block_sum_right[block]);
    block_carry_values2[lane] = sum;
    GroupMemoryBarrierWithGroupSync();
    for (uint width = 128u; width != 0u; width >>= 1u)
    {
        if (lane < width)
            block_carry_values2[lane] += block_carry_values2[lane + width];
        GroupMemoryBarrierWithGroupSync();
    }
    return block_carry_values2[0];
}
