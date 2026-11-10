// Shared exact sparse-set primitives for GPU SSA. Logical capacity lives in
// one global set, so the number of lanes never multiplies storage.

import atomics;

public static const uint SSA_SPARSE_INSERT_EXISTING = 0u;
public static const uint SSA_SPARSE_INSERTED = 1u;
public static const uint SSA_SPARSE_INSERT_FULL = 2u;

public uint ssa_sparse_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint ssa_sparse_first_slot(
    uint declaration,
    uint block,
    uint capacity)
{
    uint hash = ssa_sparse_mix(declaration ^ 0x9e3779b9u);
    hash ^= ssa_sparse_mix(block ^ 0x85ebca6bu);
    return capacity == 0u ? 0u : ssa_sparse_mix(hash) % capacity;
}

// The two-word claim is exact and nonblocking. Zero means unclaimed; valid
// ids are stored plus one. A same-declaration contender may complete the block
// claim, which is harmless: exactly one thread observes the zero-to-key block
// transition and therefore admits the logical pair.
public uint ssa_sparse_insert_key(
    uint declaration,
    uint block,
    uint capacity,
    RWStructuredBuffer<uint> declarations,
    RWStructuredBuffer<uint> blocks,
    out uint resolved_slot)
{
    resolved_slot = 0xffffffffu;
    if (capacity == 0u || declaration == 0xffffffffu || block == 0xffffffffu)
        return SSA_SPARSE_INSERT_FULL;

    uint declaration_key = declaration + 1u;
    uint block_key = block + 1u;
    uint first = ssa_sparse_first_slot(declaration, block, capacity);
    for (uint probe = 0u; probe < capacity; ++probe)
    {
        uint slot = (first + probe) % capacity;
        uint stored_declaration = declarations[slot];
        if (stored_declaration == 0u)
            stored_declaration = atomic_u32_compare_exchange(
                declarations, slot, 0u, declaration_key);
        if (stored_declaration != 0u &&
            stored_declaration != declaration_key)
            continue;

        uint stored_block = blocks[slot];
        if (stored_block == 0u)
        {
            uint prior = atomic_u32_compare_exchange(
                blocks, slot, 0u, block_key);
            if (prior == 0u)
            {
                resolved_slot = slot;
                return SSA_SPARSE_INSERTED;
            }
            stored_block = prior;
        }
        if (stored_block == block_key)
        {
            resolved_slot = slot;
            return SSA_SPARSE_INSERT_EXISTING;
        }
    }
    return SSA_SPARSE_INSERT_FULL;
}

public uint ssa_atomic_load(
    RWStructuredBuffer<uint> values,
    uint index)
{
    return atomic_u32_add(values, index, 0u);
}
