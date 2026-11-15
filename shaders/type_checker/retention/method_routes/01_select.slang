import type_checker.retention.method_routes.common;
// Match the accepted symbolic bound, with exact parameter identities. The
// solver route is the same ordinal in this instance's closed predicate list.
bool matches_bound(uint record,uint required,uint env,uint subject)
{
    uint4 fact=rt_traits[record*RT_TRAIT_WORDS];
    uint4 more=rt_traits[record*RT_TRAIT_WORDS+1u];
    uint trait=rt_dir[required*RT_DIR_WORDS].z; uint te=mr_entry(trait);
    if ((fact.y&0xffu)!=1u || more.x!=trait || te==RT_INVALID || rt_term_kind(fact.w)!=RT_KIND_NAMED) return false;
    uint4 d1=rt_dir[te*RT_DIR_WORDS+1u]; uint n=(d1.y&0xffffu)+(d1.y>>16u); uint a=0u; bool self=false;
    if (n>64u) return false;
    for (uint k=0u;k<n;k++)
    {
        uint param=rt_binders[d1.x+k]; uint4 key=rt_param_key[param];
        uint value=mr_binding(env,required,param);
        if (key.z==RT_SELF_ORDINAL) { if (subject!=fact.z) return false; self=true; }
        else { if (a>=rt_term_arity(fact.w) || value!=rt_term_arg(fact.w,a)) return false; a++; }
    }
    return self && a==rt_term_arity(fact.w);
}
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=mr_lane(id); if (i>=mr_config[2]) return;
    uint4 request=mr_requests[i];
    uint4 use=rt_uses[request.z*RT_USE_WORDS];
    uint required=mr_entry(use.w);
    if (required==RT_INVALID || rt_dir[required*RT_DIR_WORDS].y!=3u) return;
    if (mr_state[0]!=1u || request.x!=0u || request.w>=mr_h(RP_H_USES) || !sb_result_current(mr_config[0],i)) { mr_fail(i,2u); return; }
    uint4 sub=sb_results[i*SB_RESULT_WORDS];
    if (sub.y!=SB_OK || !rt_term_closed(sub.x) || rt_term_kind(sub.x)!=RT_KIND_ENV || rt_term_words(sub.x).x!=use.w) { mr_fail(i,3u); return; }
    uint caller=mr_entry(mr_instances[2u*request.w].x); uint parent=caller==RT_INVALID ? RT_INVALID : mr_entry(rt_dir[caller*RT_DIR_WORDS].z);
    if (caller==RT_INVALID) { mr_fail(i,4u); return; }
    uint own=rt_dir_trait[caller].y; uint count=own+(parent==RT_INVALID ? 0u : rt_dir_trait[parent].y);
    uint found=RT_INVALID; uint symbolic=rt_uses[request.z*RT_USE_WORDS+1u].x;
    for (uint k=0u;k<count;k++)
    {
        uint e=k<own ? caller : parent; uint ordinal=k<own ? k : k-own;
        if (matches_bound(rt_dir_trait[e].x+ordinal,required,symbolic,rt_uses[request.z*RT_USE_WORDS+1u].z))
        { if (found!=RT_INVALID) { mr_fail(i,5u); return; } found=k; }
    }
    uint at=mr_h(RP_H_USE_MAP)+request.w*RP_USE_WORDS;
    uint first=mr_routes[at+1u];
    if (found==RT_INVALID || mr_routes[at]==0u || mr_routes[at+2u]!=count || mr_routes[at+3u]!=1u ||
        first>mr_h(RP_H_OBLIGATIONS) || count>mr_h(RP_H_OBLIGATIONS)-first) { mr_fail(i,6u); return; }
    uint route=mr_h(RP_H_ROUTES)+(first+found)*RP_ROUTE_WORDS;
    if (mr_routes[route]!=1u) { mr_fail(i,7u); return; }
    uint symbol=rt_decl_key[use.w].w; uint lo=mr_routes[route+3u]; uint end=lo+mr_routes[route+4u];
    if (end>mr_h(RP_H_METHOD_ROWS)) { mr_fail(i,8u); return; }
    while (lo<end) { uint mid=lo+(end-lo)/2u; if (mr_catalog[mr_h(RP_H_CAT_METHODS)+mid*6u+1u]<symbol) lo=mid+1u; else end=mid; }
    uint method=mr_h(RP_H_CAT_METHODS)+lo*6u;
    if (lo>=mr_routes[route+3u]+mr_routes[route+4u] || mr_catalog[method+1u]!=symbol || mr_catalog[method]!=mr_routes[route+2u]) { mr_fail(i,8u); return; }
    uint target=mr_id(mr_catalog[method+2u],RP_ID_DECL); uint target_entry=mr_entry(target);
    uint bindings=mr_routes[route+5u]; uint size=mr_routes[route+6u];
    if (target_entry==RT_INVALID || rt_dir[target_entry*RT_DIR_WORDS].y!=2u || size>64u ||
        bindings>mr_h(RP_H_PROOF_BINDING_ROWS) || size>mr_h(RP_H_PROOF_BINDING_ROWS)-bindings) { mr_fail(i,9u); return; }
    mr_selected[i]=uint4(target,bindings,size,mr_catalog[method+3u]);
    for (uint b=0u;b<size;b++) { uint p=mr_h(RP_H_PROOF_BINDINGS)+(bindings+b)*8u; mr_mark(uint2(mr_proof[p+2u],mr_proof[p+3u])); }
}
