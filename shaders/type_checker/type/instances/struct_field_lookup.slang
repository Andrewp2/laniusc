// Exact GPU index for compact struct fields keyed by `(owner HIR, name id)`.

import atomics;
import hir_records;

public static const uint STRUCT_FIELD_LOOKUP_EMPTY = 0u;
public static const uint STRUCT_FIELD_LOOKUP_INVALID = 0xffffffffu;

public uint struct_field_lookup_capacity(uint row_capacity)
{
    return max(row_capacity * 2u, 1u);
}

public uint struct_field_lookup_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint struct_field_lookup_first_slot(uint owner, uint name_id, uint capacity)
{
    uint key = struct_field_lookup_mix(owner ^ 0x9e3779b9u);
    key ^= struct_field_lookup_mix(name_id ^ 0x85ebca6bu);
    return struct_field_lookup_mix(key) % capacity;
}

public bool struct_field_lookup_row_matches(
    uint row,
    uint row_count,
    uint owner,
    uint name_id,
    StructuredBuffer<HirField> fields,
    StructuredBuffer<uint> name_id_by_token,
    uint token_capacity)
{
    if (row >= row_count)
        return false;
    HirField field = fields[row];
    return field.owner == owner &&
           field.name_token < token_capacity &&
           name_id_by_token[field.name_token] == name_id &&
           owner != STRUCT_FIELD_LOOKUP_INVALID &&
           name_id != STRUCT_FIELD_LOOKUP_INVALID;
}

public void struct_field_lookup_insert(
    uint row,
    uint row_count,
    uint row_capacity,
    StructuredBuffer<HirField> fields,
    StructuredBuffer<uint> name_id_by_token,
    RWStructuredBuffer<uint> table_state)
{
    if (row >= row_count)
        return;
    HirField field = fields[row];
    if (field.owner == STRUCT_FIELD_LOOKUP_INVALID || field.name_token >= row_capacity)
        return;
    uint name_id = name_id_by_token[field.name_token];
    if (name_id == STRUCT_FIELD_LOOKUP_INVALID)
        return;

    uint capacity = struct_field_lookup_capacity(row_capacity);
    uint first = struct_field_lookup_first_slot(field.owner, name_id, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint slot = (first + probe) % capacity;
        uint state = table_state[slot];
        if (state != STRUCT_FIELD_LOOKUP_EMPTY)
        {
            uint representative = state - 1u;
            if (struct_field_lookup_row_matches(
                representative, row_count, field.owner, name_id,
                fields, name_id_by_token, row_capacity))
            {
                atomic_u32_min(table_state, slot, row + 1u);
                return;
            }
            continue;
        }
        uint prior = atomic_u32_compare_exchange(
            table_state, slot, STRUCT_FIELD_LOOKUP_EMPTY, row + 1u);
        if (prior == STRUCT_FIELD_LOOKUP_EMPTY)
            return;
        uint representative = prior - 1u;
        if (struct_field_lookup_row_matches(
            representative, row_count, field.owner, name_id,
            fields, name_id_by_token, row_capacity))
        {
            atomic_u32_min(table_state, slot, row + 1u);
            return;
        }
    }
}

public uint struct_field_lookup_find(
    uint owner,
    uint name_id,
    uint row_count,
    uint row_capacity,
    StructuredBuffer<HirField> fields,
    StructuredBuffer<uint> name_id_by_token,
    StructuredBuffer<uint> table_state)
{
    if (owner == STRUCT_FIELD_LOOKUP_INVALID || name_id == STRUCT_FIELD_LOOKUP_INVALID)
        return STRUCT_FIELD_LOOKUP_INVALID;
    uint capacity = struct_field_lookup_capacity(row_capacity);
    uint first = struct_field_lookup_first_slot(owner, name_id, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint state = table_state[(first + probe) % capacity];
        if (state == STRUCT_FIELD_LOOKUP_EMPTY)
            return STRUCT_FIELD_LOOKUP_INVALID;
        uint representative = state - 1u;
        if (struct_field_lookup_row_matches(
            representative, row_count, owner, name_id,
            fields, name_id_by_token, row_capacity))
            return representative;
    }
    return STRUCT_FIELD_LOOKUP_INVALID;
}
