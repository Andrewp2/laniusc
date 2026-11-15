import type_checker.trait_solver.retained.closed.common;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=cw_lane(id);
    if (i<cw_config[2]) cw_decl[i]=uint4(RT_INVALID,RT_INVALID,RT_INVALID,0u);
    if (i<cw_config[1]) cw_param[i]=RT_INVALID;
    if (i<cw_config[6]) cw_atom_slots[i]=0u;
    if (i<cw_terms()) cw_reach[i]=0u;
    if (i<32u) cw_state[i]=i==1u ? RT_INVALID : 0u;
}
