// One lane per (object, runtime byte): marks an object whose native runtime
// differs from the entry object's. The plan keeps only the body of an object
// whose runtime is byte-identical (link.rs shared_runtime_text_plans).

import codegen.x86.link.resident.rl_common;

uint entry_object()
{
    for (uint k = 0u; k < gRL.object_count; k += 1u)
        if (meta_word(k, 6u) == 1u)
            return k;
    return INVALID;
}

bool runtime_range(uint object, out uint start, out uint end)
{
    uint text_len, rodata_len, entry, body_start, body_end;
    object_geometry(object, text_len, rodata_len, entry, body_start, body_end);
    start = body_end;
    end = text_len >= BRIDGE_BYTES ? text_len - BRIDGE_BYTES : 0u;
    return text_len >= BRIDGE_BYTES && body_end < end;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint lane = rl_lane(tid);
    uint object = lane / max(gRL.runtime_cap_max, 1u);
    uint i = lane % max(gRL.runtime_cap_max, 1u);
    if (object >= gRL.object_count)
        return;
    uint entry = entry_object();
    if (entry == INVALID || object == entry || meta_word(object, 6u) == 1u)
        return;
    uint start, end, entry_start, entry_end;
    if (!runtime_range(object, start, end) || !runtime_range(entry, entry_start, entry_end))
        return;
    if (end - start != entry_end - entry_start || i >= end - start)
        return;
    if (object_text_byte(object, start + i) != object_text_byte(entry, entry_start + i))
        rl_objects[object * OBJECT_WORDS + OB_MISMATCH] = 1u;
}
