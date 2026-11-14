// Export step 3: one lane per canonical record of the job. Counts records by
// height, so step 6 can translate every record after all of its children
// (a child's height is below its parent's).
import type_checker.canonical.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint record = export_lane(dtid);
    if (record < CT_FIRST_RECORD || record >= min(ct_counts[CT_COUNT_NEXT_RECORD], ct_record_capacity())) return;
    uint height = ct_meta[record].y & 0xffffu;
    if (height == 0u || height >= RT_X_HEIGHTS)
    {
        rt_x_term_map[record] = RT_UNKNOWN;
        InterlockedAdd(rt_x_counts[RT_X_UNTRANSLATED], 1u);
        if (height != 0u) rt_invariant(RT_INV_HEIGHT);
        return;
    }
    InterlockedAdd(rt_x_counts[RT_X_BUCKET + height], 1u);
}
