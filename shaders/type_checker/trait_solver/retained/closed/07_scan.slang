import type_checker.trait_solver.retained.closed.common;
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID)
{
    uint i=cw_lane(id); if (i>=cw_lanes()) return;
    uint distance=cw_step[0].x; uint source=cw_step[0].y;
    for (uint part=0u;part<2u;part++)
    {
        uint4 v=source==0u ? cw_scan_a[2u*i+part] : cw_scan_b[2u*i+part];
        if (i>=distance) v+=source==0u ? cw_scan_a[2u*(i-distance)+part] : cw_scan_b[2u*(i-distance)+part];
        if (source==0u) cw_scan_b[2u*i+part]=v; else cw_scan_a[2u*i+part]=v;
    }
}
