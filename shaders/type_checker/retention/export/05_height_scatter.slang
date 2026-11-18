// Export step 5: one lane per canonical record. Places it in its height's
// block of rt_x_order. Afterwards a bucket's base word is its end.
import type_checker.canonicalization.canonical_api;
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
    if (height == 0u || height >= RT_X_HEIGHTS) return;
    uint slot;
    InterlockedAdd(rt_x_counts[RT_X_BUCKET_BASE + height], 1u, slot);
    rt_x_order[slot] = record;
}
