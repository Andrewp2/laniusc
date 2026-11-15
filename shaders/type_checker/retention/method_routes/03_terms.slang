import type_checker.retention.method_routes.common;
import constant_value;
struct Children : IRtArgs
{
    uint node; uint length;
    uint arg(uint k) { uint4 lo=mr_node(node,0u); return lo.x==2u && k==1u ? length : mr_value(mr_child(lo,mr_node(node,1u),k)); }
}
uint intern_zero(uint kind,uint3 words)
{
    RtStoredArgs args; args.base=0u; return rt_intern_term(rt_key_begin(kind,0u,0u,words),args);
}
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=mr_lane(id); mr_round_begin(i,MR_TERMS_CHANGED); if (i>=mr_config[3]) return;
    uint old=mr_config[4]==0u ? mr_values_a[i] : mr_values_b[i]; uint value=old;
    // After a round without change only the copy remains.
    if (mr_previous_changed(MR_TERMS_CHANGED) &&
        mr_reach[i]!=0u && old==RT_UNKNOWN && mr_state[0]==1u && rt_counts[RT_C_OVERFLOW]==0u)
    {
        uint4 lo=mr_node(i,0u); uint4 hi=mr_node(i,1u); uint n=mr_arity(lo); bool ready=n<=32u;
        for (uint k=0u;k<n && k<32u;k++) ready=ready && rt_is_term(mr_value(mr_child(lo,hi,k)));
        if (ready)
        {
            if (lo.x==6u) value=constant_value_is_valid(lo.yzw) ? intern_zero(RT_KIND_CC_VALUE,lo.yzw) : RT_UNKNOWN;
            else if (lo.x==5u)
            {
                uint child=mr_value(hi.xy); uint count; uint3 v;
                if (rt_term_kind(child)==RT_KIND_CC_VALUE && constant_value_to_count(rt_term_words(child),count) &&
                    count!=RT_INVALID && constant_value_from_count(count,lo.y,v)) value=intern_zero(RT_KIND_CC_VALUE,v);
            }
            else
            {
                uint kind=lo.x==1u ? RT_KIND_NAMED : lo.x==2u ? RT_KIND_ARRAY : lo.x==3u ? RT_KIND_SLICE : RT_KIND_REF;
                uint mask=0u; uint decl=0u; uint types=0u;
                Children args; args.node=i; args.length=RT_UNKNOWN;
                if (lo.x==1u)
                {
                    decl=mr_id(lo.y,RP_ID_DECL); ready=mr_entry(decl)!=RT_INVALID;
                    for (uint k=0u;k<n;k++) if ((mr_child(lo,hi,k).x&0x80000000u)!=0u) mask|=1u<<k; else types++;
                }
                if (lo.x==2u)
                {
                    uint length=mr_value(hi.zw); uint count;
                    ready=rt_term_kind(length)==RT_KIND_CC_VALUE && constant_value_to_count(rt_term_words(length),count) && count!=RT_INVALID;
                    if (ready) args.length=intern_zero(RT_KIND_CC_COUNT,uint3(count,0u,0u));
                }
                if (ready)
                {
                    RtTermKey key=rt_key_begin(kind,n,types,uint3(decl,mask,0u));
                    for (uint k=0u;k<n;k++) rt_key_fold(key,args.arg(k));
                    if (key.height<=64u) value=rt_intern_term(key,args);
                }
            }
        }
    }
    if (value!=old) mr_changed(MR_TERMS_CHANGED);
    if (mr_config[4]==0u) mr_values_b[i]=value; else mr_values_a[i]=value;
}
