import type_checker.trait_solver.closed_obligations.closed_obligation_batch;
// The count totals (cw_state 8 + column), then the batch table counts the
// solver copies into its directory (CW_COUNTS + table). They are zero
// unless the batch can be placed: no producer failure, no pending frontier,
// at least one call and every count within the host's bound (CW_BOUNDS +
// table). The fault word says why not: 1 failure, 2 frontier, 4 no call,
// 8 a count over its bound. fill_closed_obligation_batch writes nothing after a fault.

// The rows of batch table t from the totals: atoms (1), terms (5), term
// edges (6), bindings (7, 12), environments and calls (11, 15), the one
// root context (13) and obligations (16).
uint table_rows(uint t)
{
    uint c=t==1u ? 0u : t==5u ? 1u : t==6u ? 2u : (t==7u || t==12u) ? 3u :
        (t==11u || t==13u || t==15u) ? 4u : t==16u ? 5u : 8u;
    if (c==8u) return 0u;
    uint total=cw_state[8u+c];
    return t==13u ? min(total,1u) : total;
}
[shader("compute")]
[numthreads(1,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    bool program_failed = cw_state[CW_PROGRAM_FAILED] != 0u;
    if (program_failed) cw_fail(8u, 0u);
    uint fault=(cw_state[0]!=0u ? 1u : 0u) | (cw_state[5]!=0u ? 2u : 0u) | (cw_state[12]==0u ? 4u : 0u);
    if (program_failed) fault |= 32u;
    for (uint t=0u;t<18u;t++) if (table_rows(t)>cw_config[CW_BOUNDS+t]) fault|=8u;
    for (uint t=0u;t<18u;t++) cw_state[CW_COUNTS+t]=fault==0u ? table_rows(t) : 0u;
    cw_state[CW_PUBLISH]=fault==0u ? table_rows(16u) : 0u;
    cw_state[CW_PUBLISH+1u]=cw_cat_count(1u)+(fault==0u ? table_rows(1u) : 0u);
    cw_state[CW_PUBLISH+2u]=fault==0u ? table_rows(15u) : 0u;
    cw_state[CW_FAULT]=fault;
}
