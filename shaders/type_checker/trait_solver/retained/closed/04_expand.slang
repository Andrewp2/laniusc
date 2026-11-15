import type_checker.trait_solver.retained.closed.common;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint at=cw_state[3]+cw_lane(id);
    if (at>=cw_state[4]) return;
    uint t=cw_front[at];
    for (uint a=0u;a<rt_term_arity(t);a++) cw_mark(rt_term_arg(t,a));
}
