import type_checker.trait_solver.retained.closed.common;
[shader("compute")]
[numthreads(1,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint first=cw_state[4]; uint end=cw_state[2];
    cw_state[3]=first; cw_state[4]=end;
    uint groups=(end-first+255u)/256u;
    cw_indirect[0]=min(groups,65535u); cw_indirect[1]=(groups+65534u)/65535u; cw_indirect[2]=1u;
}
