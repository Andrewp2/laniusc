import type_checker.retention.projection.schema.common;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID)
{
    uint lane = ps_lane(id);
    uint n = ps_config[1]-ps_config[0];
    if (lane > n) return;
    uint a = ps_scan(lane);
    uint b = lane >= ps_config[3] ? ps_scan(lane-ps_config[3]) : 0u;
    if (b > RT_INVALID-a) InterlockedOr(ps_status[2],2u);
    if (ps_config[4] == 0u) ps_scan_b[lane] = a+b; else ps_scan_a[lane] = a+b;
    if (lane == n) ps_status[0] = a+b;
}
