// Export step 5: one lane per canonical record. Places it in its height's
// block of rt_x_order. Afterwards a bucket's base word is its end.
import type_checker.canonicalization.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;

public void scatter_retained_types_by_height(uint record)
{
    if (record < CT_FIRST_RECORD || record >= min(rt_input_ct_counts[CT_COUNT_NEXT_RECORD], export_record_capacity())) return;
    if (rt_x_term_map[record] == RT_UNKNOWN) return; // rejected by 03_heights
    uint height = rt_input_ct_meta[record].y & 0xffffu;
    if (height == 0u || height >= RT_X_HEIGHTS) return;
    uint slot;
    InterlockedAdd(rt_x_counts[RT_X_BUCKET_BASE + height], 1u, slot);
    rt_x_order[slot] = record;
}
