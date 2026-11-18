import type_checker.trait_solver.closed_obligations.closed_obligation_batch;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=cw_first()+cw_lane(id);
    if (i>=cw_end()) return;
    uint4 q=cw_instances[2u*i];
    if (q.x==0u) return; // discovery interner tombstone
    uint e=cw_entry(q.x);
    if (e==RT_INVALID || q.z!=cw_config[5]) { cw_fail(5u,i); return; }
    if (!cw_selected(i)) return;
    uint4 d1=rt_dir[e*RT_DIR_WORDS+1u];
    uint types=d1.y&0xffffu; uint constants=d1.y>>16u;
    uint tm=types>=32u ? 0xffffffffu : (1u<<types)-1u;
    uint cm=constants>=32u ? 0xffffffffu : (1u<<constants)-1u;
    if (q.z!=cw_config[5] || types>32u || constants>32u ||
        !rt_is_stored_term(q.y) || q.y>=cw_terms() || rt_term_kind(q.y)!=RT_KIND_ENV || !rt_term_closed(q.y) ||
        any(rt_term_words(q.y)!=uint3(q.x,tm,cm)) || rt_term_arity(q.y)!=types+constants ||
        (rt_term_head[q.y].x>>16u)!=types || cw_decl[q.x].y==RT_INVALID || cw_decl[q.x].z==RT_INVALID)
    { cw_fail(5u,i); return; }
    for (uint a=0u;a<types+constants;a++) cw_mark(rt_term_arg(q.y,a));
}
