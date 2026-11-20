import type_checker.trait_solver.closed_obligations.closed_obligation_batch;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=cw_lane(id); if (i>=cw_lanes() || cw_state[CW_FAULT]!=0u) return;
    uint atom_ids=cw_config[10]; uint use_map=cw_config[11];
    if (i==0u && cw_state[12]!=0u)
    {
        // A closed root context: no lexical owner, assumptions or replay origin.
        cw_put4(13u,0u,0u,uint4(0u,RT_INVALID,RT_INVALID,0u));
        cw_put4(13u,0u,4u,uint4(0u,2u,RT_INVALID,0u));
    }
    if (i<cw_terms() && cw_reach[i]!=0u)
    {
        uint kind=cw_term_kind(i); uint3 w=cw_term_words(i);
        if (kind==RT_KIND_CC_VALUE || kind==RT_KIND_CC_COUNT)
        {
            uint slot=cw_atom_slot(cw_constant(i));
            if (slot==RT_INVALID || cw_atom_slots[slot]!=i) return;
            uint a=cw_rank(i,0u); cw_put4(1u,a,0u,cw_constant(i)); cw_put4(1u,a,4u,uint4(0u,0u,0u,0u));
            uint dest=atom_ids+2u*(cw_cat_count(1u)+a);
            cw_routes[dest]=RP_ID_TERM; cw_routes[dest+1u]=i;
            return;
        }
        uint n=cw_rank(i,1u); uint edge=cw_rank(i,2u);
        uint4 low=uint4(0u,0u,0u,0u); uint4 high=low;
        if (kind==RT_KIND_NAMED)
        {
            uint arity=cw_term_arity(i);
            low=uint4(1u,cw_decl[w.x].x,arity==0u ? 0u : cw_cat_count(6u)+edge,arity);
            for (uint a=0u;a<arity;a++)
            { uint2 r=cw_ref(cw_term_arg(i,a)); cw_put(6u,edge+a,0u,r.x); cw_put(6u,edge+a,1u,r.y); }
        }
        else if (kind==RT_KIND_ARRAY) { low.x=2u; high=uint4(cw_ref(cw_term_arg(i,0u)),cw_ref(cw_term_arg(i,1u))); }
        else { low.x=kind==RT_KIND_SLICE ? 3u : 4u; high.xy=cw_ref(cw_term_arg(i,0u)); }
        cw_put4(5u,n,0u,low); cw_put4(5u,n,4u,high);
    }
    else if (i>=cw_terms())
    {
        uint instance=cw_first()+i-cw_terms(); if (!cw_selected(instance)) return;
        uint4 q=cw_instances[2u*instance]; uint e=cw_entry(q.x);
        uint4 d1=closed_rt_dir[e*RT_DIR_WORDS+1u];
        uint bindings=cw_rank(i,3u); uint call=cw_rank(i,4u); uint obligations=cw_rank(i,5u);
        uint k=cw_term_arity(q.y); uint count=cw_predicates(e); uint owner=cw_decl[q.x].y;
        cw_put4(15u,call,0u,uint4(0u,instance,RT_INVALID,cw_decl[q.x].z));
        cw_put4(15u,call,4u,uint4(call,obligations,count,0u));
        cw_put4(11u,call,0u,uint4(owner,k==0u ? 0u : bindings,k,1u)); cw_put(11u,call,4u,call);
        for (uint a=0u;a<k;a++)
        {
            uint2 r=cw_ref(cw_term_arg(q.y,a));
            cw_put(7u,bindings+a,0u,r.x); cw_put(7u,bindings+a,1u,r.y);
            uint p=rt_binders[d1.x+a]; uint position=0u;
            for (uint b=0u;b<k;b++) if (rt_binders[d1.x+b]<p) position++;
            cw_put4(12u,bindings+position,0u,uint4(call,cw_param[p],cw_cat_count(7u)+bindings+a,0u));
        }
        uint own_count=closed_rt_dir_trait[e].y;
        uint parent=cw_entry(closed_rt_dir[e*RT_DIR_WORDS].z);
        for (uint o=0u;o<count;o++)
        {
            uint predicate_owner=o<own_count ? owner : cw_decl[closed_rt_dir[parent*RT_DIR_WORDS].x].y;
            uint ordinal=o<own_count ? o : o-own_count;
            uint predicate=cw_word(2u,predicate_owner,6u)+ordinal;
            cw_put4(16u,obligations+o,0u,uint4(call,predicate,call,0u));
        }
        uint at=use_map+instance*RP_USE_WORDS;
        cw_routes[at]=call+1u; cw_routes[at+1u]=obligations; cw_routes[at+2u]=count;
    }
}
