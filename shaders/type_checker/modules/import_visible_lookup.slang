// Exact GPU index for imported declarations visible in one namespace.
//
// A slot stores an immutable visibility-row index plus one. The row columns
// contain the full `(importing module, name)` key and declaration value, so a
// single atomic publication word is sufficient and every probe compares the
// complete key.

import atomics;

public static const uint IMPORT_VISIBLE_LOOKUP_EMPTY = 0u;
public static const uint IMPORT_VISIBLE_LOOKUP_INVALID = 0xffffffffu;

public uint import_visible_lookup_capacity(uint row_capacity)
{
    return max(row_capacity * 2u, 1u);
}

public uint import_visible_lookup_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint import_visible_lookup_first_slot(uint module_id, uint name_id, uint capacity)
{
    uint key = import_visible_lookup_mix(module_id ^ 0x9e3779b9u);
    key ^= import_visible_lookup_mix(name_id ^ 0x85ebca6bu);
    return import_visible_lookup_mix(key) % capacity;
}

public bool import_visible_lookup_row_valid(
    uint row,
    uint row_count,
    StructuredBuffer<uint> module_ids,
    StructuredBuffer<uint> name_ids,
    StructuredBuffer<uint> declaration_ids)
{
    return row < row_count &&
           module_ids[row] != IMPORT_VISIBLE_LOOKUP_INVALID &&
           name_ids[row] != IMPORT_VISIBLE_LOOKUP_INVALID &&
           declaration_ids[row] != IMPORT_VISIBLE_LOOKUP_INVALID;
}

public bool import_visible_lookup_row_matches(
    uint row,
    uint row_count,
    uint module_id,
    uint name_id,
    StructuredBuffer<uint> module_ids,
    StructuredBuffer<uint> name_ids,
    StructuredBuffer<uint> declaration_ids)
{
    return import_visible_lookup_row_valid(
               row,
               row_count,
               module_ids,
               name_ids,
               declaration_ids) &&
           module_ids[row] == module_id &&
           name_ids[row] == name_id;
}

public void import_visible_lookup_insert(
    uint row,
    uint row_count,
    uint row_capacity,
    StructuredBuffer<uint> module_ids,
    StructuredBuffer<uint> name_ids,
    StructuredBuffer<uint> declaration_ids,
    RWStructuredBuffer<uint> table_state)
{
    if (!import_visible_lookup_row_valid(
        row,
        row_count,
        module_ids,
        name_ids,
        declaration_ids))
        return;

    uint capacity = import_visible_lookup_capacity(row_capacity);
    uint module_id = module_ids[row];
    uint name_id = name_ids[row];
    uint first = import_visible_lookup_first_slot(module_id, name_id, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint slot = (first + probe) % capacity;
        uint state = table_state[slot];
        if (state != IMPORT_VISIBLE_LOOKUP_EMPTY)
        {
            uint owner = state - 1u;
            if (import_visible_lookup_row_matches(
                owner,
                row_count,
                module_id,
                name_id,
                module_ids,
                name_ids,
                declaration_ids))
            {
                atomic_u32_min(table_state, slot, row + 1u);
                return;
            }
            continue;
        }

        uint prior = atomic_u32_compare_exchange(
            table_state,
            slot,
            IMPORT_VISIBLE_LOOKUP_EMPTY,
            row + 1u);
        if (prior == IMPORT_VISIBLE_LOOKUP_EMPTY)
            return;
        uint prior_owner = prior - 1u;
        if (import_visible_lookup_row_matches(
            prior_owner,
            row_count,
            module_id,
            name_id,
            module_ids,
            name_ids,
            declaration_ids))
        {
            atomic_u32_min(table_state, slot, row + 1u);
            return;
        }
    }
}

public uint import_visible_lookup_find(
    uint module_id,
    uint name_id,
    uint row_count,
    uint row_capacity,
    StructuredBuffer<uint> module_ids,
    StructuredBuffer<uint> name_ids,
    StructuredBuffer<uint> declaration_ids,
    StructuredBuffer<uint> table_state)
{
    if (module_id == IMPORT_VISIBLE_LOOKUP_INVALID ||
        name_id == IMPORT_VISIBLE_LOOKUP_INVALID)
        return IMPORT_VISIBLE_LOOKUP_INVALID;

    uint capacity = import_visible_lookup_capacity(row_capacity);
    uint first = import_visible_lookup_first_slot(module_id, name_id, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint state = table_state[(first + probe) % capacity];
        if (state == IMPORT_VISIBLE_LOOKUP_EMPTY)
            return IMPORT_VISIBLE_LOOKUP_INVALID;
        uint owner = state - 1u;
        if (import_visible_lookup_row_matches(
            owner,
            row_count,
            module_id,
            name_id,
            module_ids,
            name_ids,
            declaration_ids))
            return owner;
    }
    return IMPORT_VISIBLE_LOOKUP_INVALID;
}
