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

public struct ReduceU32Min : IPrefixScanOp<uint>
{
    public static uint identity()
    {
        return 0xffffffffu;
    }

    public static uint combine(uint left, uint right)
    {
        return min(left, right);
    }
}

public struct ReduceU32Max : IPrefixScanOp<uint>
{
    public static uint identity()
    {
        return 0u;
    }

    public static uint combine(uint left, uint right)
    {
        return max(left, right);
    }
}

public struct ReduceU32x2MinKeyValue : IPrefixScanOp<uint2>
{
    public static uint2 identity()
    {
        return uint2(0xffffffffu, 0xffffffffu);
    }

    public static uint2 combine(uint2 left, uint2 right)
    {
        if (left.x < right.x)
            return left;
        if (right.x < left.x)
            return right;
        return left.y <= right.y ? left : right;
    }
}

public struct ReduceU32x2MaxKeyMinValue : IPrefixScanOp<uint2>
{
    public static uint2 identity()
    {
        return uint2(0u, 0xffffffffu);
    }

    public static uint2 combine(uint2 left, uint2 right)
    {
        if (left.x > right.x)
            return left;
        if (right.x > left.x)
            return right;
        return left.y <= right.y ? left : right;
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

public T group_reduce_active_power_of_two<
    T,
    TOp: IPrefixScanOp<T>,
    let GSIZE: int>(
    uint lane,
    T value,
    bool active,
    inout T scratch[GSIZE])
{
    return group_reduce_power_of_two<T, TOp, GSIZE>(
        lane,
        active ? value : TOp.identity(),
        scratch);
}

public uint reduction_tree_parent_count(uint item_count)
{
    return (item_count + 1u) >> 1u;
}

public bool reduction_tree_has_right(uint item_i, uint stride, uint item_count)
{
    return item_i + stride < item_count;
}

public T reduction_tree_step_value<T, TOp: IPrefixScanOp<T>>(
    uint item_i,
    uint stride,
    uint item_count,
    StructuredBuffer<T> input)
{
    T value = input[item_i];
    uint right_i = item_i + stride;
    if (right_i < item_count)
        value = TOp.combine(value, input[right_i]);
    return value;
}
