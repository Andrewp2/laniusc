import lookup;

static const uint LOOKUP_CAPACITY = 16u;
static const uint QUERY_COUNT = 8u;
static const uint INVALID = 0xffffffffu;

StructuredBuffer<uint> lookup_keys;
StructuredBuffer<uint> lookup_values;
StructuredBuffer<uint> query_keys;

RWStructuredBuffer<uint> found_values;
RWStructuredBuffer<uint> found_flags;
RWStructuredBuffer<uint> probe_slots;
RWStructuredBuffer<uint> publish_keys;
RWStructuredBuffer<uint> publish_values;
RWStructuredBuffer<uint> publish_status;

public struct U32LookupKeyOps : IOpenAddressKeyOps<uint>
{
    public static bool valid(uint key)
    {
        return key != INVALID;
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

public struct U32LookupTable : IOpenAddressReadTable<uint, uint>
{
    public static uint key_at(uint slot)
    {
        return lookup_keys[slot];
    }

    public static uint value_at(uint slot)
    {
        return lookup_values[slot];
    }

    public static uint invalid_value()
    {
        return INVALID;
    }

    public static bool value_is_empty(uint value)
    {
        return value == INVALID;
    }
}

[shader("compute")]
[numthreads(16, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x;
    if (i < QUERY_COUNT)
    {
        uint value;
        bool found = open_address_find<uint, uint, U32LookupKeyOps, U32LookupTable>(
            query_keys[i],
            LOOKUP_CAPACITY,
            value);
        found_values[i] = value;
        found_flags[i] = found ? 1u : 0u;
        probe_slots[i] = open_address_probe_slot(query_keys[i], LOOKUP_CAPACITY, i);
    }

    if (i == 0u)
    {
        bool first = open_address_publish_min_u32_buffer<U32LookupKeyOps>(
            7u,
            12u,
            LOOKUP_CAPACITY,
            INVALID,
            publish_keys,
            publish_values);
        bool second = open_address_publish_min_u32_buffer<U32LookupKeyOps>(
            7u,
            3u,
            LOOKUP_CAPACITY,
            INVALID,
            publish_keys,
            publish_values);
        bool third = open_address_publish_min_u32_buffer<U32LookupKeyOps>(
            23u,
            9u,
            LOOKUP_CAPACITY,
            INVALID,
            publish_keys,
            publish_values);
        bool invalid = open_address_publish_min_u32_buffer<U32LookupKeyOps>(
            INVALID,
            1u,
            LOOKUP_CAPACITY,
            INVALID,
            publish_keys,
            publish_values);
        publish_status[0] = first ? 1u : 0u;
        publish_status[1] = second ? 1u : 0u;
        publish_status[2] = third ? 1u : 0u;
        publish_status[3] = invalid ? 1u : 0u;
    }
}
