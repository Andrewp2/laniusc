import type_checker.retention.method_routes.common;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=mr_lane(id);
    if (i<mr_config[2]) { mr_out[i]=uint4(0u,0u,0u,0u); mr_selected[i]=uint4(RT_INVALID,0u,0u,0u); }
    if (i<mr_config[3]) { mr_reach[i]=0u; mr_values_a[i]=RT_UNKNOWN; mr_values_b[i]=RT_UNKNOWN; }
    if (i!=0u) return;
    for (uint k=0u;k<32u;k++) mr_state[k]=k==2u ? RT_INVALID : 0u;
    bool valid=rt_counts[RT_C_READY]==1u && rt_counts[RT_C_GENERATION]==mr_config[1] && mr_h(RP_H_STATUS)==RP_VALID && mr_h(RP_H_GENERATION)==mr_config[1];
    for (uint k=0u;k<5u;k++) valid=valid && mr_h(RP_H_EPOCH+k)==mr_config[5u+k];
    valid=valid && mr_h(RP_H_STORE_DIRS)==rt_counts[RT_A_DIR] && mr_h(RP_H_STORE_DECLS)==rt_counts[RT_A_DECLS] &&
        mr_h(RP_H_STORE_TRAITS)==rt_counts[RT_A_TRAITS] && mr_h(RP_H_STORE_JOBS)==rt_counts[RT_C_JOBS];
    mr_state[0]=valid ? 1u : 0u;
    mr_state[4]=rt_counts[RT_A_TERMS]; mr_state[5]=rt_counts[RT_A_TERM_ARGS];
    mr_state[6]=rt_counts[RT_C_SPARE+RT_A_TERMS]; mr_state[7]=rt_counts[RT_C_SPARE+RT_A_TERM_ARGS];
    mr_state[8]=rt_counts[RT_C_OVERFLOW]; mr_state[9]=rt_counts[RT_C_DEMAND+RT_A_TERMS]; mr_state[10]=rt_counts[RT_C_DEMAND+RT_A_TERM_ARGS];
    rt_counts[RT_C_OVERFLOW]=0u; rt_counts[RT_C_DEMAND+RT_A_TERMS]=0u; rt_counts[RT_C_DEMAND+RT_A_TERM_ARGS]=0u;
}
