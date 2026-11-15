import type_checker.trait_solver.retained.closed.common;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint t=cw_lane(id);
    if (t>=cw_terms() || cw_reach[t]==0u) return;
    uint kind=rt_term_kind(t);
    if (kind==RT_KIND_CC_VALUE || kind==RT_KIND_CC_COUNT) cw_insert_atom(t);
}
