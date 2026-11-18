// One lane per candidate C name: inserts it into the name table that
// match_resident_c_imports.slang probes. Candidate names are distinct.

import codegen.x86.link.resident_linking.resident_c_name_lookup;

public RWStructuredBuffer<uint> cn_out;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint candidate = cn_lane(tid);
    if (candidate >= gCN.candidate_count)
        return;
    uint slot = name_hash(cn_names[candidate * 3u], cn_names[candidate * 3u + 1u]) & gCN.name_mask;
    for (uint probe = 0u; probe <= gCN.name_mask; probe += 1u)
    {
        if (atomic_u32_compare_exchange(cn_name_hash, slot, 0u, candidate + 1u) == 0u)
            return;
        slot = (slot + 1u) & gCN.name_mask;
    }
    atomic_u32_or(cn_out, 44u, BIT_HASH);
}
