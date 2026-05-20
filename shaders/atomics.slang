public uint atomic_u32_add(
    RWStructuredBuffer<uint> values,
    uint index,
    uint delta)
{
    uint prior = 0u;
    InterlockedAdd(values[index], delta, prior);
    return prior;
}

public int atomic_i32_add(
    RWStructuredBuffer<int> values,
    uint index,
    int delta)
{
    int prior = 0;
    InterlockedAdd(values[index], delta, prior);
    return prior;
}

public uint atomic_u32_min(
    RWStructuredBuffer<uint> values,
    uint index,
    uint value)
{
    uint prior = 0u;
    InterlockedMin(values[index], value, prior);
    return prior;
}

public uint atomic_u32_max(
    RWStructuredBuffer<uint> values,
    uint index,
    uint value)
{
    uint prior = 0u;
    InterlockedMax(values[index], value, prior);
    return prior;
}

public uint atomic_u32_and(
    RWStructuredBuffer<uint> values,
    uint index,
    uint mask)
{
    uint prior = 0u;
    InterlockedAnd(values[index], mask, prior);
    return prior;
}

public uint atomic_u32_or(
    RWStructuredBuffer<uint> values,
    uint index,
    uint mask)
{
    uint prior = 0u;
    InterlockedOr(values[index], mask, prior);
    return prior;
}

public uint atomic_u32_compare_exchange(
    RWStructuredBuffer<uint> values,
    uint index,
    uint compare_value,
    uint new_value)
{
    uint prior = 0u;
    InterlockedCompareExchange(
        values[index],
        compare_value,
        new_value,
        prior);
    return prior;
}
