// The term closure of a closed wave in one workgroup: each level expands
// the terms the previous level reached (cw_front[cw_state[3]..cw_state[4]),
// appended by cw_mark), until a level reaches nothing new or after
// CW_LEVELS levels. Retained type height is bounded by 64, so 65 levels
// consume any valid frontier; one still pending (cw_state[2] differs from
// cw_state[4]) is a producer failure (05_count sets cw_state[5]).
import type_checker.trait_solver.retained.closed.common;
static const uint CW_LEVELS = 65u;
groupshared uint cw_level[2];
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 local:SV_GroupThreadID)
{
    uint t=local.x;
    for (uint level=0u;level<CW_LEVELS;level++)
    {
        if (t==0u)
        {
            uint first=cw_state[4]; uint end=cw_state[2];
            cw_state[3]=first; cw_state[4]=end;
            cw_level[0]=first; cw_level[1]=end;
        }
        AllMemoryBarrierWithGroupSync();
        uint first=cw_level[0]; uint end=cw_level[1];
        if (first==end) break;
        for (uint at=first+t;at<end;at+=256u)
        {
            uint term=cw_front[at];
            for (uint a=0u;a<rt_term_arity(term);a++) cw_mark(rt_term_arg(term,a));
        }
        AllMemoryBarrierWithGroupSync();
    }
}
