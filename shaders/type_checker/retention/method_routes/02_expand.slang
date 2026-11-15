import type_checker.retention.method_routes.common;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=mr_lane(id); mr_round_begin(i,MR_EXPAND_CHANGED);
    if (!mr_previous_changed(MR_EXPAND_CHANGED)) return;
    if (i>=mr_config[3] || mr_reach[i]==0u || mr_state[0]!=1u) return;
    uint4 lo=mr_node(i,0u); uint4 hi=mr_node(i,1u); uint n=mr_arity(lo);
    if (lo.x<1u || lo.x>6u || n>32u) { InterlockedOr(mr_state[3],2u); return; }
    for (uint k=0u;k<n;k++) mr_mark(mr_child(lo,hi,k));
}
