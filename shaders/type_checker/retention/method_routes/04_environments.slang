import type_checker.retention.method_routes.common;
uint selected_binding(uint4 selected,uint param)
{
    for (uint b=0u;b<selected.z;b++)
    {
        uint at=mr_h(RP_H_PROOF_BINDINGS)+(selected.y+b)*8u;
        if (mr_id(mr_proof[at+1u],RP_ID_PARAM)==param) return mr_value(uint2(mr_proof[at+2u],mr_proof[at+3u]));
    }
    return RT_UNKNOWN;
}
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    // Both loops must have reached their fixed point: the last recorded
    // round changed nothing. Otherwise the host records more rounds, up to
    // the bound, where this pass runs regardless (mr_config[11]).
    bool converged=mr_state[MR_EXPAND_CHANGED+mr_round()]==0u && mr_state[MR_TERMS_CHANGED+mr_round()]==0u;
    if (!converged && mr_config[11]==0u)
    {
        if (mr_lane(id)==0u)
        {
            mr_state[MR_PENDING]=1u;
            // The next batch's first evaluation round must run: reach may
            // have grown after this batch's last evaluation round.
            mr_state[MR_TERMS_CHANGED+mr_round()]=1u;
        }
        return;
    }
    if (mr_lane(id)==0u) mr_state[MR_PENDING]=0u;
    uint i=mr_lane(id); if (i>=mr_config[2]) return;
    uint4 selected=mr_selected[i]; if (selected.x==RT_INVALID || mr_out[i].w!=0u) return;
    uint4 request=mr_requests[i]; uint required_decl=rt_uses[request.z*RT_USE_WORDS].w;
    uint required=mr_entry(required_decl); uint target=mr_entry(selected.x);
    uint4 d1=rt_dir[target*RT_DIR_WORDS+1u];
    uint types=d1.y&0xffffu; uint constants=d1.y>>16u; uint n=types+constants;
    uint4 original=rt_dir[required*RT_DIR_WORDS+1u]; uint on=(original.y&0xffffu)+(original.y>>16u);
    if (types>32u || constants>32u || on>64u || mr_state[3]!=0u) { mr_fail(i,10u); return; }
    uint env=sb_results[i*SB_RESULT_WORDS].x;
    MrArgs args; args.base=i*64u;
    for (uint k=0u;k<n;k++)
    {
        uint param=rt_binders[d1.x+k]; uint4 key=rt_param_key[param]; uint value=RT_UNKNOWN;
        if (key.x==selected.x)
        {
            // Required and implementation methods have different ParamIds;
            // their own domains and ordinals correspond by the admitted
            // method contract. Inherited impl parameters use proof bindings.
            for (uint a=0u;a<on;a++)
            {
                uint rp=rt_binders[original.x+a]; uint4 rk=rt_param_key[rp];
                if (rk.x==required_decl && rk.y==key.y && rk.z==key.z) value=mr_binding(env,required,rp);
            }
        }
        else value=selected_binding(selected,param);
        bool type=value>0u && value<RT_FIRST_TERM;
        uint kind=rt_term_kind(value);
        type=type || kind==RT_KIND_NAMED || kind==RT_KIND_ARRAY || kind==RT_KIND_SLICE || kind==RT_KIND_REF;
        bool valid=k<types ? key.y==RT_DOMAIN_TYPE && type : key.y==RT_DOMAIN_CONST && kind==RT_KIND_CC_VALUE && rt_term_words(value).x==key.w;
        if (!valid || !rt_term_closed(value)) { mr_fail(i,11u); return; }
        mr_args[args.base+k]=value;
    }
    uint tm=types==32u ? 0xffffffffu : (1u<<types)-1u; uint cm=constants==32u ? 0xffffffffu : (1u<<constants)-1u;
    RtTermKey key=rt_key_begin(RT_KIND_ENV,n,types,uint3(selected.x,tm,cm));
    for (uint k=0u;k<n;k++) rt_key_fold(key,args.arg(k));
    uint result=rt_intern_term(key,args);
    if (!rt_is_stored_term(result)) { mr_fail(i,12u); return; }
    mr_out[i]=uint4(selected.x,result,selected.w,1u);
}
