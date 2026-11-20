import type_checker.retention.method_routes.retained_method_route_workspace;
public void publish_retained_method_routes(uint requests, uint4 request)
{
    if (mr_state[MR_PENDING]!=0u) return; // more rounds follow
    uint failure=mr_state[2];
    if (failure<requests) { mr_state[16]=request.z; mr_state[17]=request.w; mr_state[18]=mr_out[failure].w; }
    uint overflow=rt_counts[RT_C_OVERFLOW];
    mr_state[11]=overflow; mr_state[12]=rt_counts[RT_C_DEMAND+RT_A_TERMS]; mr_state[13]=rt_counts[RT_C_DEMAND+RT_A_TERM_ARGS];
    rt_counts[RT_C_OVERFLOW]=mr_state[8]; rt_counts[RT_C_DEMAND+RT_A_TERMS]=mr_state[9]; rt_counts[RT_C_DEMAND+RT_A_TERM_ARGS]=mr_state[10];
    if (overflow!=0u)
    {
        rt_counts[RT_A_TERMS]=mr_state[4]; rt_counts[RT_A_TERM_ARGS]=mr_state[5];
        rt_counts[RT_C_SPARE+RT_A_TERMS]=mr_state[6]; rt_counts[RT_C_SPARE+RT_A_TERM_ARGS]=mr_state[7];
        mr_state[0]=3u;
    }
    else mr_state[0]=mr_state[0]==1u && mr_state[1]==0u && mr_state[3]==0u ? 2u : 4u;
}
