import type_checker.trait_solver.closed_obligations.closed_obligation_batch;

public void clear_closed_workspace(uint i)
{
    if (i<cw_config[2]) cw_decl[i]=uint4(RT_INVALID,RT_INVALID,RT_INVALID,0u);
    if (i<cw_config[1]) cw_param[i]=RT_INVALID;
    if (i<cw_config[6]) cw_atom_slots[i]=0u;
    if (i<cw_terms()) cw_reach[i]=0u;
    if (i<CW_STATE_WORDS) cw_state[i]=i==1u ? RT_INVALID : 0u;
}

public void index_closed_catalog(uint i)
{
    if (i==0u)
    {
        bool valid=cw_source_routes[RP_H_STATUS]==RP_VALID && closed_rt_counts[RT_C_READY]==1u &&
            closed_rt_counts[RT_C_GENERATION]==cw_config[5] && cw_source_routes[RP_H_GENERATION]==cw_config[5] &&
            cw_source_routes[RP_H_STORE_DIRS]==closed_rt_counts[RT_A_DIR] &&
            cw_source_routes[RP_H_STORE_JOBS]==closed_rt_counts[RT_C_JOBS] &&
            cw_source_routes[RP_H_STORE_DECLS]==closed_rt_counts[RT_A_DECLS] &&
            cw_source_routes[RP_H_STORE_TRAITS]==closed_rt_counts[RT_A_TRAITS];
        if (!valid) cw_fail(1u,0u);
    }
    if (i<cw_cat_count(1u))
    {
        uint kind=cw_word(1u,i,0u);
        if (kind==1u || kind==2u)
        {
            uint d=cw_id(i,RP_ID_DECL);
            if (d<cw_config[2]) cw_decl[d].x=i; else cw_fail(4u,i);
        }
        if (kind==5u)
        {
            uint p=cw_id(i,RP_ID_PARAM);
            if (p<cw_config[1]) cw_param[p]=i; else cw_fail(4u,i);
        }
        if (kind==12u) cw_insert_atom(0x80000000u|i);
    }
    if (i<cw_cat_count(2u))
    {
        uint d=cw_id(cw_word(2u,i,0u),RP_ID_DECL);
        if (d<cw_config[2]) cw_decl[d].y=i; else cw_fail(4u,i);
    }
    if (i<cw_cat_count(4u))
    {
        uint d=cw_id(cw_word(4u,i,0u),RP_ID_DECL);
        if (d<cw_config[2]) cw_decl[d].z=i; else cw_fail(4u,i);
    }
}

public void mark_closed_roots(uint local)
{
    uint i = cw_first() + local;
    if (i>=cw_end()) return;
    uint4 q=cw_instances[2u*i];
    if (q.x==0u) return; // discovery interner tombstone
    uint e=cw_entry(q.x);
    if (e==RT_INVALID || q.z!=cw_config[5]) { cw_fail(5u,i); return; }
    if (!cw_selected(i)) return;
    uint4 d1=closed_rt_dir[e*RT_DIR_WORDS+1u];
    uint types=d1.y&0xffffu; uint constants=d1.y>>16u;
    uint tm=types>=32u ? 0xffffffffu : (1u<<types)-1u;
    uint cm=constants>=32u ? 0xffffffffu : (1u<<constants)-1u;
    if (q.z!=cw_config[5] || types>32u || constants>32u ||
        !rt_is_stored_term(q.y) || q.y>=cw_terms() || cw_term_kind(q.y)!=RT_KIND_ENV || !cw_term_closed(q.y) ||
        any(cw_term_words(q.y)!=uint3(q.x,tm,cm)) || cw_term_arity(q.y)!=types+constants ||
        (closed_rt_term_head[q.y].x>>16u)!=types || cw_decl[q.x].y==RT_INVALID || cw_decl[q.x].z==RT_INVALID)
    { cw_fail(5u,i); return; }
    for (uint a=0u;a<types+constants;a++) cw_mark(cw_term_arg(q.y,a));
}

public void intern_closed_constants(uint t)
{
    uint kind=cw_term_kind(t);
    if (kind==RT_KIND_CC_VALUE || kind==RT_KIND_CC_COUNT) cw_insert_atom(t);
}

public void count_closed_rows(uint i)
{
    uint4 low=uint4(0u,0u,0u,0u); uint4 high=low;
    if (i<cw_terms() && cw_reach[i]!=0u)
    {
        uint kind=cw_term_kind(i);
        if (kind==RT_KIND_CC_VALUE || kind==RT_KIND_CC_COUNT)
        {
            uint slot=cw_atom_slot(cw_constant(i));
            if (slot==RT_INVALID) cw_fail(3u,i);
            else low.x=cw_atom_slots[slot]==i ? 1u : 0u;
        }
        else if (kind==RT_KIND_NAMED || kind==RT_KIND_ARRAY || kind==RT_KIND_SLICE || kind==RT_KIND_REF)
        {
            low.y=1u; low.z=kind==RT_KIND_NAMED ? cw_term_arity(i) : 0u;
            if (low.z>32u || (kind==RT_KIND_NAMED && (cw_term_words(i).x>=cw_config[2] ||
                cw_decl[cw_term_words(i).x].x==RT_INVALID))) cw_fail(6u,i);
        }
        else cw_fail(6u,i);
    }
    else if (i>=cw_terms())
    {
        uint instance=cw_first()+i-cw_terms();
        if (cw_selected(instance))
        {
            uint4 q=cw_instances[2u*instance]; uint e=cw_entry(q.x);
            low.w=cw_term_arity(q.y); high.x=1u; high.y=cw_predicates(e);
        }
    }
    cw_scan_low[i] = low;
    cw_scan_high[i] = high;
    // A frontier left after the recorded rounds asks the host for more
    // rounds; after the 65-round bound it is a producer failure (code 7).
    if (i==0u) cw_state[5]=cw_state[2]!=cw_state[4] ? 1u : 0u;
}
