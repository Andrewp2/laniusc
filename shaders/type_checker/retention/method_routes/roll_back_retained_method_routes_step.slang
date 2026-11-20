import type_checker.retention.method_routes.retained_method_route_workspace;
public void roll_back_retained_method_routes(uint i)
{
    if (mr_state[0]!=3u) return;
    uint n; uint stride; rt_term_slot.GetDimensions(n,stride);
    if (i<n && rt_term_slot[i]>=mr_state[4]) rt_term_slot[i]=0u;
}
