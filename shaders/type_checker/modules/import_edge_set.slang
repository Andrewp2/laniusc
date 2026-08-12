// Exact GPU hash set for resolved directed module-import edges.
//
// A slot stores the producing import row plus one, leaving zero as empty.  The
// immutable import relation supplies the key, so publication needs only one
// atomic word and queries still compare both module ids exactly.

import atomics;

public static const uint IMPORT_EDGE_SET_EMPTY = 0u;
public static const uint IMPORT_EDGE_SET_INVALID = 0xffffffffu;
public static const uint IMPORT_EDGE_STATUS_OK = 0u;

public interface IImportEdgeStatusSource
{
    static uint status(uint row);
}

public uint import_edge_set_capacity(uint import_capacity)
{
    return max(import_capacity * 2u, 1u);
}

public uint import_edge_set_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint import_edge_set_first_slot(uint source, uint target, uint capacity)
{
    uint key = import_edge_set_mix(source ^ 0x9e3779b9u);
    key ^= import_edge_set_mix(target ^ 0x85ebca6bu);
    return import_edge_set_mix(key) % capacity;
}

public bool import_edge_row_valid<TStatus: IImportEdgeStatusSource>(
    uint row,
    uint import_count,
    StructuredBuffer<uint> import_module_id,
    StructuredBuffer<uint> import_target_module_id)
{
    return row < import_count &&
           TStatus.status(row) == IMPORT_EDGE_STATUS_OK &&
           import_module_id[row] != IMPORT_EDGE_SET_INVALID &&
           import_target_module_id[row] != IMPORT_EDGE_SET_INVALID;
}

public bool import_edge_row_matches<TStatus: IImportEdgeStatusSource>(
    uint row,
    uint import_count,
    uint source,
    uint target,
    StructuredBuffer<uint> import_module_id,
    StructuredBuffer<uint> import_target_module_id)
{
    return import_edge_row_valid<TStatus>(
               row,
               import_count,
               import_module_id,
               import_target_module_id) &&
           import_module_id[row] == source &&
           import_target_module_id[row] == target;
}

public void import_edge_set_insert<TStatus: IImportEdgeStatusSource>(
    uint row,
    uint import_count,
    StructuredBuffer<uint> import_module_id,
    StructuredBuffer<uint> import_target_module_id,
    RWStructuredBuffer<uint> import_edge_set_state)
{
    if (!import_edge_row_valid<TStatus>(
        row,
        import_count,
        import_module_id,
        import_target_module_id))
        return;

    uint capacity = import_edge_set_capacity(import_count);
    uint source = import_module_id[row];
    uint target = import_target_module_id[row];
    uint first = import_edge_set_first_slot(source, target, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint slot = (first + probe) % capacity;
        uint state = import_edge_set_state[slot];
        if (state != IMPORT_EDGE_SET_EMPTY)
        {
            uint owner = state - 1u;
            if (import_edge_row_matches<TStatus>(
                owner,
                import_count,
                source,
                target,
                import_module_id,
                import_target_module_id))
                return;
            continue;
        }

        uint prior = atomic_u32_compare_exchange(
            import_edge_set_state,
            slot,
            IMPORT_EDGE_SET_EMPTY,
            row + 1u);
        if (prior == IMPORT_EDGE_SET_EMPTY)
            return;
        uint prior_owner = prior - 1u;
        if (import_edge_row_matches<TStatus>(
            prior_owner,
            import_count,
            source,
            target,
            import_module_id,
            import_target_module_id))
            return;
    }
}

public bool import_edge_set_contains<TStatus: IImportEdgeStatusSource>(
    uint source,
    uint target,
    uint import_count,
    StructuredBuffer<uint> import_module_id,
    StructuredBuffer<uint> import_target_module_id,
    StructuredBuffer<uint> import_edge_set_state)
{
    uint capacity = import_edge_set_capacity(import_count);
    uint first = import_edge_set_first_slot(source, target, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint state = import_edge_set_state[(first + probe) % capacity];
        if (state == IMPORT_EDGE_SET_EMPTY)
            return false;
        if (import_edge_row_matches<TStatus>(
            state - 1u,
            import_count,
            source,
            target,
            import_module_id,
            import_target_module_id))
            return true;
    }
    return false;
}
