// Exact GPU declaration index keyed by `(module, namespace, name)`.
//
// A slot stores a declaration id plus one. Declaration columns contain the
// complete immutable key, so collisions are resolved by exact comparison.

import atomics;

public static const uint DECL_LOOKUP_EMPTY = 0u;
public static const uint DECL_LOOKUP_INVALID = 0xffffffffu;

public uint decl_lookup_capacity(uint declaration_count)
{
    return max(declaration_count * 2u, 1u);
}

public uint decl_lookup_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint decl_lookup_first_slot(
    uint module_id,
    uint namespace_id,
    uint name_id,
    uint capacity)
{
    uint key = decl_lookup_mix(module_id ^ 0x9e3779b9u);
    key ^= decl_lookup_mix(namespace_id ^ 0xc2b2ae35u);
    key ^= decl_lookup_mix(name_id ^ 0x85ebca6bu);
    return decl_lookup_mix(key) % capacity;
}

public bool decl_lookup_matches(
    uint declaration,
    uint declaration_count,
    uint module_id,
    uint namespace_id,
    uint name_id,
    StructuredBuffer<uint> declaration_modules,
    StructuredBuffer<uint> declaration_namespaces,
    StructuredBuffer<uint> declaration_names)
{
    return declaration < declaration_count &&
           declaration_modules[declaration] == module_id &&
           declaration_namespaces[declaration] == namespace_id &&
           declaration_names[declaration] == name_id;
}

public void decl_lookup_insert(
    uint declaration,
    uint declaration_count,
    StructuredBuffer<uint> declaration_modules,
    StructuredBuffer<uint> declaration_namespaces,
    StructuredBuffer<uint> declaration_names,
    RWStructuredBuffer<uint> table_state)
{
    if (declaration >= declaration_count)
        return;
    uint module_id = declaration_modules[declaration];
    uint namespace_id = declaration_namespaces[declaration];
    uint name_id = declaration_names[declaration];
    if (module_id == DECL_LOOKUP_INVALID || name_id == DECL_LOOKUP_INVALID)
        return;

    uint capacity = decl_lookup_capacity(declaration_count);
    uint first = decl_lookup_first_slot(module_id, namespace_id, name_id, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint slot = (first + probe) % capacity;
        uint state = table_state[slot];
        if (state != DECL_LOOKUP_EMPTY)
        {
            uint representative = state - 1u;
            if (decl_lookup_matches(
                representative, declaration_count, module_id, namespace_id, name_id,
                declaration_modules, declaration_namespaces, declaration_names))
            {
                atomic_u32_min(table_state, slot, declaration + 1u);
                return;
            }
            continue;
        }

        uint prior = atomic_u32_compare_exchange(
            table_state, slot, DECL_LOOKUP_EMPTY, declaration + 1u);
        if (prior == DECL_LOOKUP_EMPTY)
            return;
        uint representative = prior - 1u;
        if (decl_lookup_matches(
            representative, declaration_count, module_id, namespace_id, name_id,
            declaration_modules, declaration_namespaces, declaration_names))
        {
            atomic_u32_min(table_state, slot, declaration + 1u);
            return;
        }
    }
}

public uint decl_lookup_find(
    uint module_id,
    uint namespace_id,
    uint name_id,
    uint declaration_count,
    StructuredBuffer<uint> declaration_modules,
    StructuredBuffer<uint> declaration_namespaces,
    StructuredBuffer<uint> declaration_names,
    StructuredBuffer<uint> table_state)
{
    if (module_id == DECL_LOOKUP_INVALID || name_id == DECL_LOOKUP_INVALID)
        return DECL_LOOKUP_INVALID;
    uint capacity = decl_lookup_capacity(declaration_count);
    uint first = decl_lookup_first_slot(module_id, namespace_id, name_id, capacity);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint state = table_state[(first + probe) % capacity];
        if (state == DECL_LOOKUP_EMPTY)
            return DECL_LOOKUP_INVALID;
        uint declaration = state - 1u;
        if (decl_lookup_matches(
            declaration, declaration_count, module_id, namespace_id, name_id,
            declaration_modules, declaration_namespaces, declaration_names))
            return declaration;
    }
    return DECL_LOOKUP_INVALID;
}
