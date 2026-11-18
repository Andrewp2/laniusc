// Clear the exact-name hash table and hash every compacted source/language name.

import name_hash_common;

RWStructuredBuffer<uint> unique_name_count;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i < gParams.table_half_capacity)
    {
        name_hash_table_a[i] = INVALID;
        name_hash_table_b[i] = INVALID;
    }
    if (i == 0u)
        unique_name_count[0u] = 0u;
    if (i >= active_name_count())
        return;

    uint2 hash = hash_name(name_spans[i]);
    name_hash_lo[i] = hash.x;
    name_hash_hi[i] = hash.y;
}
