// Shared exact sparse-set and bounded-work-queue primitives for GPU SSA.
//
// Persistent workgroups are schedulers only. Logical capacity lives in one
// global set and queue, so changing worker occupancy never multiplies storage.

import atomics;

public static const uint SSA_SPARSE_INSERT_EXISTING = 0u;
public static const uint SSA_SPARSE_INSERTED = 1u;
public static const uint SSA_SPARSE_INSERT_FULL = 2u;

public static const uint SSA_WORK_HEAD = 0u;
public static const uint SSA_WORK_TAIL = 1u;
public static const uint SSA_WORK_OUTSTANDING = 2u;
public static const uint SSA_WORK_RESERVED = 3u;

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

// Publishes value+1 so a zeroed queue slot is visibly not ready. Outstanding
// is incremented before tail publication; the source item remains outstanding
// until its workgroup has finished discovering every successor.
public bool ssa_work_publish(
    uint value,
    uint capacity,
    RWStructuredBuffer<uint> state,
    RWStructuredBuffer<uint> queue,
    out uint required)
{
    atomic_u32_add(state, SSA_WORK_OUTSTANDING, 1u);
    uint row = atomic_u32_add(state, SSA_WORK_TAIL, 1u);
    required = row + 1u;
    if (row >= capacity)
    {
        atomic_u32_add(state, SSA_WORK_OUTSTANDING, 0xffffffffu);
        return false;
    }
    uint ignored;
    InterlockedExchange(queue[row], value + 1u, ignored);
    return true;
}

// Returns one published value. A producer that has exposed a tail row is
// already resident and will publish its slot; atomic polling avoids observing
// an ordinary non-atomic payload write before it is ready.
public bool ssa_work_try_pop(
    uint capacity,
    RWStructuredBuffer<uint> state,
    RWStructuredBuffer<uint> queue,
    out uint value)
{
    for (;;)
    {
        uint head = ssa_atomic_load(state, SSA_WORK_HEAD);
        uint tail = ssa_atomic_load(state, SSA_WORK_TAIL);
        if (head >= tail) return false;
        uint prior = atomic_u32_compare_exchange(
            state, SSA_WORK_HEAD, head, head + 1u);
        if (prior != head) continue;
        if (head >= capacity) continue;

        uint published = 0u;
        while (published == 0u)
            published = ssa_atomic_load(queue, head);
        value = published - 1u;
        return true;
    }
}

// Reserves up to max_count already-published queue rows with one head CAS.
// One workgroup can then process the contiguous batch cooperatively instead
// of contending once per lane. Rows beyond capacity are consumed but omitted;
// their producers already reported capacity and withdrew their outstanding
// contribution.
public bool ssa_work_try_pop_batch(
    uint capacity,
    uint max_count,
    RWStructuredBuffer<uint> state,
    out uint begin,
    out uint count)
{
    begin = 0u;
    count = 0u;
    for (;;)
    {
        uint head = ssa_atomic_load(state, SSA_WORK_HEAD);
        uint tail = ssa_atomic_load(state, SSA_WORK_TAIL);
        if (head >= tail) return false;
        uint end = min(tail, head + max_count);
        uint prior = atomic_u32_compare_exchange(
            state, SSA_WORK_HEAD, head, end);
        if (prior != head) continue;
        if (head >= capacity) return false;
        begin = head;
        count = min(end, capacity) - head;
        return count != 0u;
    }
}

public uint ssa_work_read_published(
    RWStructuredBuffer<uint> queue,
    uint row)
{
    uint published = 0u;
    while (published == 0u)
        published = ssa_atomic_load(queue, row);
    return published - 1u;
}

public bool ssa_work_quiescent(RWStructuredBuffer<uint> state)
{
    return ssa_atomic_load(state, SSA_WORK_OUTSTANDING) == 0u;
}

public void ssa_work_finish(RWStructuredBuffer<uint> state)
{
    atomic_u32_add(state, SSA_WORK_OUTSTANDING, 0xffffffffu);
}

public void ssa_work_finish_batch(
    RWStructuredBuffer<uint> state,
    uint count)
{
    atomic_u32_add(state, SSA_WORK_OUTSTANDING, 0u - count);
}
