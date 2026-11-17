import type_checker.retention.method_routes.common;
// Reachability marking from the selected bindings, all levels in one
// workgroup.
struct Expand : IMrLevel
{
    void run(uint lane,uint level)
    {
        if (mr_state[0]!=1u) return;
        for (uint i=lane;i<mr_config[3];i+=256u)
        {
            if (mr_reach[i]==0u) continue;
            uint4 lo=mr_node(i,0u); uint4 hi=mr_node(i,1u); uint n=mr_arity(lo);
            if (lo.x<1u || lo.x>6u || n>32u) { InterlockedOr(mr_state[3],2u); continue; }
            for (uint k=0u;k<n;k++) mr_mark_at(mr_child(lo,hi,k),level%3u);
        }
    }
}
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 local:SV_GroupThreadID)
{
    Expand expand; mr_levels(local.x,MR_EXPAND_CHANGED,expand);
}
