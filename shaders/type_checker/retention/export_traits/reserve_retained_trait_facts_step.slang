// Export step reserve_retained_trait_facts (one lane): reserve the job's trait-fact records, the
// predicates first, then the bindings, and keep the trait-fact scan totals
// for steps write_retained_trait_facts. The per-row marks and the per-owner counts must agree; a
// disagreement means a fact has no owner block.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;


public void reserve_retained_trait_facts(uint4 total)
{
    for (uint i = 0u; i < 4u; i++) rt_x_counts[RT_X_TRAIT_TOTAL + i] = total[i];
    if (total.x != total.z || total.y != total.w) rt_invariant(RT_INV_TRAIT_ORDER);
    rt_x_counts[RT_X_BASE + RT_A_TRAITS] = rt_alloc(RT_A_TRAITS, total.z + total.w);
}
