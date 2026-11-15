import type_checker.retention.discovery.dg_common;
// Complete structural order, without hashes or a recursive per-lane walk.
// Children have smaller heights and already have deterministic ranks.
int compare_term(uint a, uint b)
{
    if (a == b) return 0;
    if (a == RT_INVALID) return 1; if (b == RT_INVALID) return -1;
    uint4 x = rt_term_head[a]; uint4 y = rt_term_head[b];
    int c = dg_cmp(x.x,y.x); if(c != 0) return c;
    uint kind = x.x & 255u;
    if(kind == RT_KIND_NAMED || kind == RT_KIND_ENV) c = dg_decl_cmp(x.y,y.y);
    else c = dg_cmp(x.y,y.y);
    if(c != 0) return c;
    c = dg_cmp(x.z,y.z); if(c != 0) return c;
    c = dg_cmp(x.w,y.w); if(c != 0) return c;
    uint arity = rt_term_arity(a);
    for(uint i=0u;i<arity;i++)
    {
        uint left = rt_term_arg(a,i); uint right = rt_term_arg(b,i);
        left = left < RT_FIRST_TERM ? left : dg_term_rank[left];
        right = right < RT_FIRST_TERM ? right : dg_term_rank[right];
        c = dg_cmp(left,right); if(c != 0) return c;
    }
    return 0;
}
struct TermOrder : IDgCompare
{
    uint base;
    int compare(uint a, uint b) { return compare_term(a, b); }
    uint load(uint index) { return dg_term_order[base + index]; }
    void store(uint index, uint value) { dg_term_order[base + index] = value; }
}
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID, uint3 group: SV_GroupID, uint3 thread: SV_GroupThreadID)
{
    uint lane=dg_lane(id); uint mode=dg_config[0];
    if(mode==5u)
    {
        TermOrder order; order.base=dg_config[12];
        dg_sort_block(order, group.x + group.y * 65535u, thread.x, dg_config[13], dg_config[10]);
        return;
    }
    if(mode==4u) { if(lane<dg_config[13]) dg_term_order[lane]=RT_INVALID; return; }
    if(mode==6u)
    {
        // Level counts recorded after each wave's resolution, over the
        // store's term capacity. A term without a valid height is left to
        // mode 1, which reports it as before.
        uint term=lane+RT_FIRST_TERM;
        if(term >= rt_counts[RT_A_TERMS] || rt_term_head[term].x == 0u || !rt_term_closed(term)) return;
        uint height=rt_term_height(term);
        if(height != 0u && height < 128u) InterlockedAdd(dg_levels[height],1u);
        return;
    }
    if(mode < 2u)
    {
        uint term=lane+RT_FIRST_TERM;
        if(term >= rt_counts[RT_A_TERMS] || rt_term_head[term].x == 0u || !rt_term_closed(term)) return;
        uint height=rt_term_height(term);
        if(height == 0u || height >= 128u) { dg_status[10]=8u; return; }
        if(mode==0u) InterlockedAdd(dg_levels[height],1u);
        else
        {
            uint ordinal; InterlockedAdd(dg_levels[256u+height],1u,ordinal);
            dg_term_order[dg_levels[128u+height]+ordinal]=term;
        }
        return;
    }
    if(lane >= dg_config[13]) return;
    uint base=dg_config[12];
    if(mode==2u)
    {
        uint other=lane ^ dg_config[11]; if(other<=lane || other>=dg_config[13]) return;
        uint a=dg_term_order[base+lane]; uint b=dg_term_order[base+other];
        bool ascending=(lane & dg_config[10])==0u;
        if((compare_term(a,b)>0)==ascending)
        { dg_term_order[base+lane]=b; dg_term_order[base+other]=a; }
    }
    else
    {
        uint term=dg_term_order[base+lane];
        if(term!=RT_INVALID) dg_term_rank[term]=RT_FIRST_TERM+base+lane;
    }
}
