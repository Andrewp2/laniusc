import prefix_scan;

public struct ReduceU32Add : IPrefixScanOp<uint>
{
    public static uint identity()
    {
        return 0u;
    }

    public static uint combine(uint left, uint right)
    {
        return left + right;
    }
}

public T group_reduce_power_of_two<
    T,
    TOp: IPrefixScanOp<T>,
    let GSIZE: int>(
    uint lane,
    T value,
    inout T scratch[GSIZE])
{
    scratch[lane] = value;
    GroupMemoryBarrierWithGroupSync();

    for (uint stride = uint(GSIZE) >> 1u; stride > 0u; stride >>= 1u)
    {
        if (lane < stride)
            scratch[lane] = TOp.combine(scratch[lane], scratch[lane + stride]);
        GroupMemoryBarrierWithGroupSync();
    }

    return scratch[0u];
}
