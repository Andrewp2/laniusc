// Export step 3: one lane per canonical record of the job. Counts records by
// height, so step 6 can translate every record after all of its children
// (a child's height is below its parent's).
import type_checker.canonical.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;

bool published(uint record, uint2 hash)
{
    uint mask = ct_slot_capacity() - 1u;
    uint slot = ct_probe_start(hash);
    for (uint probe = 0u; probe <= mask; probe++)
    {
        uint occupant = ct_slot[slot];
        if (occupant == record) return true;
        if (occupant == 0u) return false;
        slot = (slot + 1u) & mask;
    }
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint record = export_lane(dtid);
    if (record < CT_FIRST_RECORD || record >= min(ct_counts[CT_COUNT_NEXT_RECORD], ct_record_capacity())) return;
    // Losing canonical candidates can leave complete records below the
    // allocation watermark. Translating them races to intern the same term.
    uint4 meta = ct_meta[record];
    if (!published(record, meta.zw))
    {
        rt_x_term_map[record] = RT_UNKNOWN;
        return;
    }
    uint height = meta.y & 0xffffu;
    if (height == 0u || height >= RT_X_HEIGHTS)
    {
        rt_x_term_map[record] = RT_UNKNOWN;
        InterlockedAdd(rt_x_counts[RT_X_UNTRANSLATED], 1u);
        if (height != 0u) rt_invariant(RT_INV_HEIGHT);
        return;
    }
    InterlockedAdd(rt_x_counts[RT_X_BUCKET + height], 1u);
}
