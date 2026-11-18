// Resolve exact-name table entries to deterministic representative input ids.

import name_hash_common;
import atomics;

RWStructuredBuffer<uint> sorted_name_id;
RWStructuredBuffer<uint> name_id_by_input;
RWStructuredBuffer<uint> name_id_by_token;
RWStructuredBuffer<uint> language_name_id;
RWStructuredBuffer<uint> unique_name_count;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint name_i = linear_thread_id(dtid);
    if (name_i >= active_name_count())
        return;

    uint capacity = table_capacity();
    uint slot = first_slot(name_i);
    uint representative = INVALID;
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint candidate = table_load(slot);
        if (candidate == INVALID)
            break;
        if (names_equal(candidate, name_i))
        {
            representative = candidate;
            break;
        }
        slot += 1u;
        if (slot == capacity)
            slot = 0u;
    }
    if (representative == INVALID)
    {
        record_hash_table_error(name_i);
        return;
    }

    sorted_name_id[name_i] = representative;
    name_id_by_input[name_i] = representative;
    NameSpan span = name_spans[name_i];
    if (span.kind == NAME_KIND_LANGUAGE_SYMBOL)
        language_name_id[span.token_index] = representative;
    else
        name_id_by_token[span.token_index] = representative;
    if (representative == name_i)
        atomic_u32_add(unique_name_count, 0u, 1u);
}
