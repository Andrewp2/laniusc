// Instance table ranks (instance_table.slang): IT_RANK_SPLIT lanes per
// closure instance with a key. Its entry index is the number of keys ordering before
// it and its virtual row base their row count, so the table follows
// (function row, ct_shash) whatever order the closure found the instances
// in. Two equal keys flag a collision and the host ignores the table.
import type_checker.closure.instance_closure;
import type_checker.closure.instance_table;

static const uint INVALID = 0xffffffffu;
static const uint TILE = 256u;
static const uint SPLIT = IT_RANK_SPLIT;

// The keys of the tile every lane compares against: the workgroup loads
// each key once per tile instead of each lane loading every key.
groupshared uint4 g_keys[TILE];
// Each instance's SPLIT lanes are adjacent in the workgroup; they combine
// their counts here.
groupshared uint3 g_part[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint index = lane / SPLIT;
    uint part = lane % SPLIT;
    uint instances = it_instances();
    uint4 key = index < instances ? instance_table_keys[index] : uint4(INVALID, 0u, 0u, 0u);
    bool live = key.x != INVALID;
    if (instance_table_counts[IT_COUNT_ENTRIES] > IT_RANK_LIMIT)
    {
        if (live && part == 0u) it_flag(IT_FLAG_ENTRIES);
        return;
    }
    uint rank = 0u;
    uint base = 0u;
    bool collision = false;
    // Every lane takes part in each tile's load, whether its own key is
    // live or not. Lane `part` of an instance compares the tile's entries
    // part, part + SPLIT, ...
    for (uint tile = 0u; tile < instances; tile += TILE)
    {
        uint other = tile + ltid.x;
        g_keys[ltid.x] = other < instances ? instance_table_keys[other] : uint4(INVALID, 0u, 0u, 0u);
        GroupMemoryBarrierWithGroupSync();
        // Entries past the instances hold INVALID keys. The comparisons
        // have no branches, so the unrolled loads overlap.
        if (live)
        {
            [unroll(8)]
            for (uint j = part; j < TILE; j += SPLIT)
            {
                uint4 candidate = g_keys[j];
                bool counted = candidate.x != INVALID && tile + j != index;
                bool equal = all(candidate.xyz == key.xyz);
                collision = collision || (counted && equal);
                bool before = counted && !equal && it_key_less(candidate, key);
                rank += before ? 1u : 0u;
                base += before ? candidate.w : 0u;
            }
        }
        GroupMemoryBarrierWithGroupSync();
    }
    g_part[ltid.x] = uint3(rank, base, collision ? 1u : 0u);
    GroupMemoryBarrierWithGroupSync();
    if (!live || part != 0u) return;
    bool collided = false;
    rank = 0u;
    base = 0u;
    for (uint k = 0u; k < SPLIT; k++)
    {
        uint3 counts = g_part[ltid.x + k];
        rank += counts.x;
        base += counts.y;
        collided = collided || counts.z != 0u;
    }
    if (collided) it_flag(IT_FLAG_COLLISION);
    uint4 instance = instance_closure_instances[2u * index];
    instance_table[2u * rank] = uint4(key.x, key.w, instance.x, base);
    instance_table[2u * rank + 1u] = uint4(index, instance.z, IT_SOURCE_LOCAL, 0u);
}
