import type_checker.retention.discovery.dg_common;
int compare_instance(uint a,uint b)
{
    if(a==b) return 0;
    if(a==RT_INVALID) return 1; if(b==RT_INVALID) return -1;
    uint4 x=dg_instances[2u*a]; uint4 y=dg_instances[2u*b];
    int c=dg_decl_cmp(x.x,y.x);
    return c!=0 ? c : dg_cmp(dg_term_rank[x.y],dg_term_rank[y.y]);
}
struct InstanceOrder : IDgCompare
{
    int compare(uint a, uint b) { return compare_instance(a, b); }
    uint load(uint index) { return dg_order[index]; }
    void store(uint index, uint value) { dg_order[index] = value; }
}
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID, uint3 group: SV_GroupID, uint3 thread: SV_GroupThreadID)
{
    if(dg_config[0]==3u)
    {
        InstanceOrder order;
        dg_sort_block(order, group.x + group.y * 65535u, thread.x, dg_config[13], dg_config[10]);
        return;
    }
    uint lane=dg_lane(id); if(lane>=dg_config[13]) return;
    if(dg_config[0]==0u)
    {
        dg_order[lane]=lane<dg_status[0] && dg_instances[2u*lane].x!=0u ? lane : RT_INVALID;
    }
    else if(dg_config[0]==1u)
    {
        uint other=lane ^ dg_config[11]; if(other<=lane || other>=dg_config[13]) return;
        uint a=dg_order[lane]; uint b=dg_order[other];
        bool ascending=(lane & dg_config[10])==0u;
        if((compare_instance(a,b)>0)==ascending) { dg_order[lane]=b; dg_order[other]=a; }
    }
    else if(lane<dg_status[1]) dg_rank[dg_order[lane]]=lane;
}
