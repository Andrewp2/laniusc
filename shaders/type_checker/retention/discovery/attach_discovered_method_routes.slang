import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.attach_discovered_method_route_step;
StructuredBuffer<uint4> mr_out;
// Method-route state: this pass shares their submit and runs only after
// they finished without failure (word 0 is 2, MR_PENDING word 28 clear).
StructuredBuffer<uint> mr_state;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    if (mr_state[29] != 0u)
    {
        if (dg_lane(id) == 0u) dg_status[31] = 1u;
        return;
    }
    // It may also share resolution's submit: then it runs only when
    // resolution left no failure or overflow (status 12).
    // In a chain (config 8 set), routes that did not finish or failed
    // stop it with code 13: the host runs the attempt again without it.
    if (dg_config[8]!=0u && dg_lane(id)==0u && (mr_state[0]!=2u || mr_state[28]!=0u) && dg_status[10]==0u)
        dg_status[10]=13u;
    if (mr_state[0]!=2u || mr_state[28]!=0u || dg_status[12]!=0u) return;
    uint i=dg_lane(id); if (i>=dg_status[7]) return;
    uint4 route = mr_out[i];
    uint environment = route.y;
    if (route.w == 1u && dg_req_meta[i].x == 0u && (environment & RT_PARAM_BIT) != 0u)
        environment = mr_out[environment & ~RT_PARAM_BIT].y;
    attach_discovered_method_route(i, route, environment, dg_config[6]);
}
