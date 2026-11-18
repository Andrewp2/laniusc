// Start interning the resident dependency page (one lane): its nodes are
// the round-0 candidates of intern_dependency_types. The table, records and
// overflow bits are kept.
import type_checker.canonicalization.canonical_api;
import shared.semantics.dependency_interface;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    ct_counts[CT_COUNT_PENDING] = dependency_type_count();
    ct_counts[CT_COUNT_ROUND] = 0u;
    ct_counts[CT_COUNT_FRONTIER] = 0u;
    ct_counts[CT_COUNT_FRONTIER + 1u] = 0u;
    ct_counts[CT_COUNT_FINAL] = 0u;
}
