// Insert names in parallel, resolving hash collisions with exact byte equality.

import name_hash_common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint name_i = linear_thread_id(dtid);
    if (name_i >= active_name_count())
        return;

    uint capacity = table_capacity();
    uint slot = first_slot(name_i);
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint representative = table_load(slot);
        if (representative == INVALID)
        {
            representative = table_claim(slot, name_i);
            if (representative == INVALID)
                return;
        }
        if (names_equal(representative, name_i))
        {
            table_min(slot, name_i);
            return;
        }
        slot += 1u;
        if (slot == capacity)
            slot = 0u;
    }
    record_hash_table_error(name_i);
}
