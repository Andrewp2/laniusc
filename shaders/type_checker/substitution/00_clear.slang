// Reset substitution state for one type-check job: the memo, the counters,
// the row of each ID, the call environments and the field closure's marks.
import type_checker.canonical.canonical_api;
import type_checker.substitution.ct_subst;
import type_checker.substitution.ct_rows;
import type_checker.substitution.call_env;
import type_checker.substitution.ct_expand;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    uint count; uint stride;
    ct_subst_memo.GetDimensions(count, stride);
    if (i < count) ct_subst_memo[i] = uint4(0u, 0u, 0u, 0u);
    if (i < ct_row_of_capacity()) ct_row_of[i] = CT_ROW_INVALID;
    call_env_ct.GetDimensions(count, stride);
    if (i < count) call_env_ct[i] = uint2(CT_NONE, CT_NONE);
    if (i < CT_SUBST_COUNT_WORDS) ct_subst_counts[i] = 0u;
    ct_expand_mark.GetDimensions(count, stride);
    if (i < count) ct_expand_mark[i] = 0u;
    if (i < CT_EXPAND_COUNT_WORDS) ct_expand_counts[i] = 0u;
}
