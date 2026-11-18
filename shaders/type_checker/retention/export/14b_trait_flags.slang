// Export step 14b: one lane per HIR row index, covering the predicate and
// method-core tables (both have at most one entry per HIR row). Writes the
// trait-fact scan flags (trait_common.slang): each exported generic-bound
// predicate marks its bound row (x) and counts at its owner (z); each method
// of a trait impl marks its row (y) and counts at its impl (w). A
// generic-bound predicate without an exportable owner is an invariant
// failure: its fact would otherwise be silently omitted.
import shared.syntax.hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;
import type_checker.retention.export.trait_common;

// The trait-fact scan's own counters (the 08 kernels read RT_X_SCAN_N and
// write their totals here when bound for this scan).
globallycoherent RWStructuredBuffer<uint> rt_x_tcounts;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = export_lane(dtid);
    if (lane == 0u) rt_x_tcounts[RT_X_SCAN_N] = hir_count();
    if (lane < predicate_rows())
    {
        HirPredicate predicate = compact_predicates[lane];
        if ((predicate.metadata & 0xffu) == PREDICATE_GENERIC_BOUND)
        {
            uint owner = predicate_owner_row(predicate);
            if (owner == 0xffffffffu) rt_invariant(RT_INV_TRAIT_FACT);
            else
            {
                InterlockedOr(rt_x_tflags[predicate.bound].x, 1u);
                InterlockedAdd(rt_x_tflags[owner].z, 1u);
            }
        }
    }
    if (lane < method_rows())
    {
        uint impl = binding_impl_row(lane);
        if (impl != 0xffffffffu)
        {
            InterlockedOr(rt_x_tflags[compact_method_cores[lane].node].y, 1u);
            InterlockedAdd(rt_x_tflags[impl].w, 1u);
        }
    }
}
