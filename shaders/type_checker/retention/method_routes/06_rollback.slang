import type_checker.retention.method_routes.common;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    if (mr_state[0]!=3u) return;
    uint i=mr_lane(id); uint n; uint stride; rt_term_slot.GetDimensions(n,stride);
    if (i<n && rt_term_slot[i]>=mr_state[4]) rt_term_slot[i]=0u;
}
