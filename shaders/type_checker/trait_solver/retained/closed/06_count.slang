import type_checker.trait_solver.retained.closed.common;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=cw_lane(id); if (i>=cw_lanes()) return;
    uint4 low=uint4(0u,0u,0u,0u); uint4 high=low;
    if (i<cw_terms() && cw_reach[i]!=0u)
    {
        uint kind=rt_term_kind(i);
        if (kind==RT_KIND_CC_VALUE || kind==RT_KIND_CC_COUNT)
        {
            uint slot=cw_atom_slot(cw_constant(i));
            if (slot==RT_INVALID) cw_fail(3u,i);
            else low.x=cw_atom_slots[slot]==i ? 1u : 0u;
        }
        else if (kind==RT_KIND_NAMED || kind==RT_KIND_ARRAY || kind==RT_KIND_SLICE || kind==RT_KIND_REF)
        {
            low.y=1u; low.z=kind==RT_KIND_NAMED ? rt_term_arity(i) : 0u;
            if (low.z>32u || (kind==RT_KIND_NAMED && (rt_term_words(i).x>=cw_config[2] ||
                cw_decl[rt_term_words(i).x].x==RT_INVALID))) cw_fail(6u,i);
        }
        else cw_fail(6u,i);
    }
    else if (i>=cw_terms())
    {
        uint instance=cw_first()+i-cw_terms();
        if (cw_selected(instance))
        {
            uint4 q=cw_instances[2u*instance]; uint e=cw_entry(q.x);
            low.w=rt_term_arity(q.y); high.x=1u; high.y=cw_predicates(e);
        }
    }
    cw_scan_a[2u*i]=low; cw_scan_a[2u*i+1u]=high;
    if (i==0u && cw_state[2]!=cw_state[4]) cw_fail(7u,0u);
}
