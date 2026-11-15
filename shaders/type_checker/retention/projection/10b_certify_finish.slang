// Root ABI certification, last step: one lane. Sets READY_ABI (bit 1) in
// the root readiness record when the record is this build's, its routes are
// published (bit 0) and 10_certify rejected no use.
import type_checker.retention.projection.pj_common;

RWStructuredBuffer<uint4> rr_readiness;
globallycoherent RWStructuredBuffer<uint> nc_cert;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u) return;
    uint4 readiness = rr_readiness[0u];
    if (readiness.x != rt_counts[RT_C_GENERATION] || (readiness.y & 1u) == 0u)
    {
        InterlockedOr(nc_cert[2], 0x100u);
        return;
    }
    if (nc_cert[0] == 0u) rr_readiness[0u] = uint4(readiness.x, readiness.y | 2u, readiness.z, readiness.w);
}
