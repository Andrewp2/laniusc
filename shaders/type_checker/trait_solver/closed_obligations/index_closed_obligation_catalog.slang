import type_checker.trait_solver.closed_obligations.closed_obligation_batch;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=cw_lane(id);
    if (i==0u)
    {
        bool valid=cw_source_routes[RP_H_STATUS]==RP_VALID && rt_counts[RT_C_READY]==1u &&
            rt_counts[RT_C_GENERATION]==cw_config[5] && cw_source_routes[RP_H_GENERATION]==cw_config[5] &&
            cw_source_routes[RP_H_STORE_DIRS]==rt_counts[RT_A_DIR] &&
            cw_source_routes[RP_H_STORE_JOBS]==rt_counts[RT_C_JOBS] &&
            cw_source_routes[RP_H_STORE_DECLS]==rt_counts[RT_A_DECLS] &&
            cw_source_routes[RP_H_STORE_TRAITS]==rt_counts[RT_A_TRAITS];
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
