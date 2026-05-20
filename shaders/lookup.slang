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

public interface IOpenAddressReadTable<TKey, TValue>
{
    static TKey key_at(uint slot);
    static TValue value_at(uint slot);
    static TValue invalid_value();
    static bool value_is_empty(TValue value);
}

public interface IOpenAddressPublishMinTable<TKey, TValue>
{
    static TKey key_at(uint slot);
    static void store_key(uint slot, TKey key);
    static TValue invalid_value();
    static bool value_is_empty(TValue value);
    static void compare_exchange_empty_value(uint slot, TValue value, out TValue old_value);
    static void publish_min_value(uint slot, TValue value, out TValue old_value);
}

public interface IOpenAddressValueOps<TValue>
{
    static TValue invalid_value();
    static bool value_is_empty(TValue value);
}

public struct OpenAddressU32InvalidMaxValueOps : IOpenAddressValueOps<uint>
{
    public static uint invalid_value()
    {
        return 0xffffffffu;
    }

    public static bool value_is_empty(uint value)
    {
        return value == 0xffffffffu;
    }
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

public bool open_address_find_limited<
    TKey,
    TValue,
    TKeyOps: IOpenAddressKeyOps<TKey>,
    TTable: IOpenAddressReadTable<TKey, TValue>>(
    TKey key,
    uint capacity,
    uint max_probes,
    out TValue value)
{
    value = TTable.invalid_value();
    if (capacity == 0u || !TKeyOps.valid(key))
        return false;

    uint hash = TKeyOps.hash(key);
    uint probe_limit = min(capacity, max_probes);
    [loop]
    for (uint probe = 0u; probe < probe_limit; probe += 1u)
    {
        uint slot = open_address_probe_hash(hash, capacity, probe);
        TValue candidate = TTable.value_at(slot);
        if (TTable.value_is_empty(candidate))
            return false;
        if (TKeyOps.equal(TTable.key_at(slot), key))
        {
            value = candidate;
            return true;
        }
    }
    return false;
}

public bool open_address_find<
    TKey,
    TValue,
    TKeyOps: IOpenAddressKeyOps<TKey>,
    TTable: IOpenAddressReadTable<TKey, TValue>>(
    TKey key,
    uint capacity,
    out TValue value)
{
    return open_address_find_limited<TKey, TValue, TKeyOps, TTable>(
        key,
        capacity,
        capacity,
        value);
}

public bool open_address_find_buffer_limited<
    TKey,
    TValue,
    TKeyOps: IOpenAddressKeyOps<TKey>,
    TValueOps: IOpenAddressValueOps<TValue>>(
    TKey key,
    uint capacity,
    uint max_probes,
    StructuredBuffer<TKey> lookup_key,
    StructuredBuffer<TValue> lookup_value,
    out TValue value)
{
    value = TValueOps.invalid_value();
    if (capacity == 0u || !TKeyOps.valid(key))
        return false;

    uint hash = TKeyOps.hash(key);
    uint probe_limit = min(capacity, max_probes);
    [loop]
    for (uint probe = 0u; probe < probe_limit; probe += 1u)
    {
        uint slot = open_address_probe_hash(hash, capacity, probe);
        TValue candidate = lookup_value[slot];
        if (TValueOps.value_is_empty(candidate))
            return false;
        if (TKeyOps.equal(lookup_key[slot], key))
        {
            value = candidate;
            return true;
        }
    }
    return false;
}

public bool open_address_find_buffer<
    TKey,
    TValue,
    TKeyOps: IOpenAddressKeyOps<TKey>,
    TValueOps: IOpenAddressValueOps<TValue>>(
    TKey key,
    uint capacity,
    StructuredBuffer<TKey> lookup_key,
    StructuredBuffer<TValue> lookup_value,
    out TValue value)
{
    return open_address_find_buffer_limited<TKey, TValue, TKeyOps, TValueOps>(
        key,
        capacity,
        capacity,
        lookup_key,
        lookup_value,
        value);
}

public bool open_address_publish_min<
    TKey,
    TValue,
    TKeyOps: IOpenAddressKeyOps<TKey>,
    TTable: IOpenAddressPublishMinTable<TKey, TValue>>(
    TKey key,
    TValue value,
    uint capacity)
{
    if (capacity == 0u || !TKeyOps.valid(key) || TTable.value_is_empty(value))
        return false;

    uint hash = TKeyOps.hash(key);
    [loop]
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint slot = open_address_probe_hash(hash, capacity, probe);
        TValue old_value = TTable.invalid_value();
        TTable.compare_exchange_empty_value(slot, value, old_value);
        if (TTable.value_is_empty(old_value))
        {
            TTable.store_key(slot, key);
            return true;
        }
        if (TKeyOps.equal(TTable.key_at(slot), key))
        {
            TValue old_min = TTable.invalid_value();
            TTable.publish_min_value(slot, value, old_min);
            return true;
        }
    }
    return false;
}

public bool open_address_publish_min_u32_buffer<
    TKeyOps: IOpenAddressKeyOps<uint>>(
    uint key,
    uint value,
    uint capacity,
    uint invalid_value,
    RWStructuredBuffer<uint> lookup_key,
    RWStructuredBuffer<uint> lookup_value)
{
    if (capacity == 0u || !TKeyOps.valid(key) || value == invalid_value)
        return false;

    uint hash = TKeyOps.hash(key);
    [loop]
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint slot = open_address_probe_hash(hash, capacity, probe);
        uint old_value = atomic_u32_compare_exchange(
            lookup_value,
            slot,
            invalid_value,
            value);
        if (old_value == invalid_value)
        {
            lookup_key[slot] = key;
            return true;
        }
        if (TKeyOps.equal(lookup_key[slot], key))
        {
            atomic_u32_min(lookup_value, slot, value);
            return true;
        }
    }
    return false;
}
