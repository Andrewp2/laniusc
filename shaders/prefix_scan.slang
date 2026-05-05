groupshared int prefix_scan_i32_values[256];
groupshared uint2 prefix_scan_u32x2_values[256];

inline int prefix_scan_i32_256(uint lane, int value)
{
    const uint GSIZE = 256u;

    prefix_scan_i32_values[lane] = value;
    GroupMemoryBarrierWithGroupSync();

    for (uint offs = 1u; offs < GSIZE; offs <<= 1u)
    {
        int x = prefix_scan_i32_values[lane];
        if (lane >= offs)
            x += prefix_scan_i32_values[lane - offs];
        GroupMemoryBarrierWithGroupSync();
        prefix_scan_i32_values[lane] = x;
        GroupMemoryBarrierWithGroupSync();
    }

    return prefix_scan_i32_values[lane];
}

inline uint2 prefix_scan_u32x2_256(uint lane, uint2 value)
{
    const uint GSIZE = 256u;

    prefix_scan_u32x2_values[lane] = value;
    GroupMemoryBarrierWithGroupSync();

    for (uint offs = 1u; offs < GSIZE; offs <<= 1u)
    {
        uint2 x = prefix_scan_u32x2_values[lane];
        if (lane >= offs)
            x += prefix_scan_u32x2_values[lane - offs];
        GroupMemoryBarrierWithGroupSync();
        prefix_scan_u32x2_values[lane] = x;
        GroupMemoryBarrierWithGroupSync();
    }

    return prefix_scan_u32x2_values[lane];
}
