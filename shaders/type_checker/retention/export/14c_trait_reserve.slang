// Export step 14c (one lane): reserve the job's trait-fact records, the
// predicates first, then the bindings, and keep the trait-fact scan totals
// for steps 14d. The per-row marks and the per-owner counts must agree; a
// disagreement means a fact has no owner block.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;

StructuredBuffer<uint> rt_x_tcounts;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint4 total = uint4(rt_x_tcounts[RT_X_SCAN_TOTAL], rt_x_tcounts[RT_X_SCAN_TOTAL + 1u],
        rt_x_tcounts[RT_X_SCAN_TOTAL + 2u], rt_x_tcounts[RT_X_SCAN_TOTAL + 3u]);
    for (uint i = 0u; i < 4u; i++) rt_x_counts[RT_X_TRAIT_TOTAL + i] = total[i];
    if (total.x != total.z || total.y != total.w) rt_invariant(RT_INV_TRAIT_ORDER);
    rt_x_counts[RT_X_BASE + RT_A_TRAITS] = rt_alloc(RT_A_TRAITS, total.z + total.w);
}
