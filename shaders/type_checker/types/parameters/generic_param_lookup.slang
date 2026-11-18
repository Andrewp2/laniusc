// Exact GPU index for declaration generic parameters.
//
// The table publishes one representative compact row for each full
// `(owner token, interned name)` key. Consumers validate the requested kind
// against the row, while duplicate validation compares every row with the
// representative selected by atomic minimum.

import atomics;

public static const uint GENERIC_PARAM_LOOKUP_EMPTY = 0u;
public static const uint GENERIC_PARAM_LOOKUP_INVALID = 0xffffffffu;

public uint generic_param_lookup_capacity(uint row_capacity)
{
    return max(row_capacity * 2u, 1u);
}

public uint generic_param_lookup_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint generic_param_lookup_first_slot(uint owner, uint name_id, uint capacity)
{
    uint key = generic_param_lookup_mix(owner ^ 0x9e3779b9u);
    key ^= generic_param_lookup_mix(name_id ^ 0x85ebca6bu);
    return generic_param_lookup_mix(key) % capacity;
}

public bool generic_param_lookup_row_matches(
    uint row,
    uint row_count,
    uint owner,
    uint name_id,
    StructuredBuffer<uint> owners,
    StructuredBuffer<uint> names)
{
    return row < row_count &&
           owners[row] == owner &&
           names[row] == name_id &&
           owner != GENERIC_PARAM_LOOKUP_INVALID &&
           name_id != GENERIC_PARAM_LOOKUP_INVALID;
}

public void generic_param_lookup_insert(
    uint row,
    uint row_count,
    uint row_capacity,
    StructuredBuffer<uint> owners,
    StructuredBuffer<uint> names,
    RWStructuredBuffer<uint> table_state)
{
    if (row >= row_count)
        return;
    uint owner = owners[row];
    uint name_id = names[row];
    if (owner == GENERIC_PARAM_LOOKUP_INVALID || name_id == GENERIC_PARAM_LOOKUP_INVALID)
        return;

    uint capacity = generic_param_lookup_capacity(row_capacity);
    uint first = generic_param_lookup_first_slot(owner, name_id, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint slot = (first + probe) % capacity;
        uint state = table_state[slot];
        if (state != GENERIC_PARAM_LOOKUP_EMPTY)
        {
            uint representative = state - 1u;
            if (generic_param_lookup_row_matches(
                representative, row_count, owner, name_id, owners, names))
            {
                atomic_u32_min(table_state, slot, row + 1u);
                return;
            }
            continue;
        }

        uint prior = atomic_u32_compare_exchange(
            table_state, slot, GENERIC_PARAM_LOOKUP_EMPTY, row + 1u);
        if (prior == GENERIC_PARAM_LOOKUP_EMPTY)
            return;
        uint representative = prior - 1u;
        if (generic_param_lookup_row_matches(
            representative, row_count, owner, name_id, owners, names))
        {
            atomic_u32_min(table_state, slot, row + 1u);
            return;
        }
    }
}

public uint generic_param_lookup_find(
    uint owner,
    uint name_id,
    uint row_count,
    uint row_capacity,
    StructuredBuffer<uint> owners,
    StructuredBuffer<uint> names,
    StructuredBuffer<uint> table_state)
{
    if (owner == GENERIC_PARAM_LOOKUP_INVALID || name_id == GENERIC_PARAM_LOOKUP_INVALID)
        return GENERIC_PARAM_LOOKUP_INVALID;
    uint capacity = generic_param_lookup_capacity(row_capacity);
    uint first = generic_param_lookup_first_slot(owner, name_id, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint state = table_state[(first + probe) % capacity];
        if (state == GENERIC_PARAM_LOOKUP_EMPTY)
            return GENERIC_PARAM_LOOKUP_INVALID;
        uint representative = state - 1u;
        if (generic_param_lookup_row_matches(
            representative, row_count, owner, name_id, owners, names))
            return representative;
    }
    return GENERIC_PARAM_LOOKUP_INVALID;
}
