// Instance table ranks (instance_table.slang): one lane per closure
// instance with a key. Its entry index is the number of keys ordering before
// it and its virtual row base their row count, so the table follows
// (function row, ct_shash) whatever order the closure found the instances
// in. Two equal keys flag a collision and the host ignores the table.
import type_checker.closure.instance_closure;
import type_checker.closure.instance_table;

static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint index = dtid.x + dtid.y * 16776960u;
    uint instances = it_instances();
    if (index >= instances) return;
    uint4 key = instance_table_keys[index];
    if (key.x == INVALID) return;
    if (instance_table_counts[IT_COUNT_ENTRIES] > IT_RANK_LIMIT)
    {
        it_flag(IT_FLAG_ENTRIES);
        return;
    }
    uint rank = 0u;
    uint base = 0u;
    for (uint other = 0u; other < instances; other++)
    {
        uint4 candidate = instance_table_keys[other];
        if (candidate.x == INVALID || other == index) continue;
        if (all(candidate.xyz == key.xyz)) it_flag(IT_FLAG_COLLISION);
        else if (it_key_less(candidate, key))
        {
            rank++;
            base += candidate.w;
        }
    }
    uint4 instance = instance_closure_instances[2u * index];
    instance_table[2u * rank] = uint4(key.x, key.w, instance.x, base);
    instance_table[2u * rank + 1u] = uint4(index, instance.z, IT_SOURCE_LOCAL, 0u);
}
