import type_checker.trait_solver.retained.closed.common;
[shader("compute")]
[numthreads(1,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    for (uint c=0u;c<8u;c++) cw_state[8u+c]=cw_rank(cw_lanes(),c);
}
