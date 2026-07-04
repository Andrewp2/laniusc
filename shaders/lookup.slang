import atomics;

public uint open_address_capacity(uint item_count, uint load_factor)
{
    return max(item_count * load_factor, 1u);
}

public interface IOpenAddressKeyOps<TKey>
{
    static bool valid(TKey key);
    static uint hash(TKey key);
    static bool equal(TKey left, TKey right);
}

public struct OpenAddressU32InvalidMaxKeyOps : IOpenAddressKeyOps<uint>
{
    public static bool valid(uint key)
    {
        return key != 0xffffffffu;
    }

    public static uint hash(uint key)
    {
        return key;
    }

    public static bool equal(uint left, uint right)
    {
        return left == right;
    }
}

public uint open_address_probe_hash(uint hash, uint capacity, uint probe)
{
    if (capacity == 0u)
        return 0u;
    return ((hash % capacity) + probe) % capacity;
}

public uint open_address_probe_slot(uint key, uint capacity, uint probe)
{
    return open_address_probe_hash(key, capacity, probe);
}

public bool open_address_publish_min_u32_buffer<
    TKeyOps: IOpenAddressKeyOps<uint>>(
    uint key,
    uint value,
    uint capacity,
    uint invalid_key,
    uint invalid_value,
    RWStructuredBuffer<uint> lookup_key,
    RWStructuredBuffer<uint> lookup_value)
{
    if (capacity == 0u || !TKeyOps.valid(key) || key == invalid_key || value == invalid_value)
        return false;

    uint hash = TKeyOps.hash(key);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint slot = open_address_probe_hash(hash, capacity, probe);
        uint old_key = atomic_u32_compare_exchange(
            lookup_key,
            slot,
            invalid_key,
            key);
        if (old_key == invalid_key || TKeyOps.equal(old_key, key))
        {
            atomic_u32_min(lookup_value, slot, value);
            return true;
        }
    }
    return false;
}
