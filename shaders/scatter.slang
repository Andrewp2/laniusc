import atomics;

public static const uint SCATTER_INACTIVE_KEY = 0xffffffffu;

public struct CompactScatterSlot
{
    public uint active;
    public uint dst;
}

public interface IScatterSink<T>
{
    static void store(uint dst, T value);
}

public interface IScatterKeyEquality<T>
{
    static bool equal(T left, T right);
}

public interface IStableRadixScatterSource<T>
{
    static uint active_count();
    static T inactive_value();
    static T ordered_value(uint order_i);
    static uint radix_key(T value, uint key_step);
}

public struct ScatterU32KeyEquality : IScatterKeyEquality<uint>
{
    public static bool equal(uint left, uint right)
    {
        return left == right;
    }
}

public CompactScatterSlot compact_scatter_slot(uint flag, uint exclusive_prefix)
{
    CompactScatterSlot slot;
    slot.active = flag != 0u ? 1u : 0u;
    slot.dst = exclusive_prefix;
    return slot;
}

public uint exclusive_from_inclusive(uint inclusive, uint value)
{
    return inclusive - value;
}

public uint radix_block_bucket_slot(uint block_idx, uint bucket, uint radix_bucket_count)
{
    return block_idx * radix_bucket_count + bucket;
}

public uint stable_radix_dst(uint bucket_base, uint block_bucket_prefix, uint local_rank)
{
    return bucket_base + block_bucket_prefix + local_rank;
}

public uint segment_item_dst(uint segment_prefix, uint local_i)
{
    return segment_prefix + local_i;
}

public bool scatter_dst_in_bounds(uint dst, uint capacity)
{
    return dst != SCATTER_INACTIVE_KEY && dst < capacity;
}

public bool compact_scatter_slot_active(CompactScatterSlot slot)
{
    return slot.active != 0u;
}

public bool compact_scatter_slot_in_bounds(CompactScatterSlot slot, uint capacity)
{
    return compact_scatter_slot_active(slot) && scatter_dst_in_bounds(slot.dst, capacity);
}

public bool scatter_store<T>(
    RWStructuredBuffer<T> output,
    uint dst,
    uint capacity,
    T value)
{
    if (!scatter_dst_in_bounds(dst, capacity))
        return false;
    output[dst] = value;
    return true;
}

public bool scatter_emit<T, TSink: IScatterSink<T>>(
    uint dst,
    uint capacity,
    T value)
{
    if (!scatter_dst_in_bounds(dst, capacity))
        return false;
    TSink.store(dst, value);
    return true;
}

public bool compact_scatter_store<T>(
    CompactScatterSlot slot,
    RWStructuredBuffer<T> output,
    uint capacity,
    T value)
{
    if (slot.active == 0u)
        return false;
    return scatter_store<T>(output, slot.dst, capacity, value);
}

public bool compact_scatter_emit<T, TSink: IScatterSink<T>>(
    CompactScatterSlot slot,
    uint capacity,
    T value)
{
    if (!compact_scatter_slot_in_bounds(slot, capacity))
        return false;
    TSink.store(slot.dst, value);
    return true;
}

public uint atomic_counter_add(
    RWStructuredBuffer<uint> counters,
    uint counter_i,
    uint delta)
{
    return atomic_u32_add(counters, counter_i, delta);
}

public bool reserve_counter_slot(
    RWStructuredBuffer<uint> counters,
    uint counter_i,
    uint capacity,
    out uint slot)
{
    slot = atomic_counter_add(counters, counter_i, 1u);
    return slot < capacity;
}

public bool reserve_active_counter_slot(
    bool active,
    RWStructuredBuffer<uint> counters,
    uint counter_i,
    uint capacity,
    out uint slot)
{
    slot = SCATTER_INACTIVE_KEY;
    if (!active)
        return false;
    return reserve_counter_slot(counters, counter_i, capacity, slot);
}

public bool first_reservation(uint prior_count)
{
    return prior_count == 0u;
}

public bool reservation_over_capacity(uint prior_count, uint capacity)
{
    return prior_count >= capacity;
}
