// Root ABI certification, last step: one lane. Sets READY_ABI (bit 1) in
// the root readiness record when the record is this build's, its routes are
// published (bit 0) and certify_retained_native_abi rejected no use.
import type_checker.retention.projection.retained_projection_workspace;

import type_checker.retention.projection.certify_retained_native_abi_step;

public void finalize_retained_native_abi()
{
    uint4 readiness = rr_readiness[0u];
    if (readiness.x != rt_counts[RT_C_GENERATION] || (readiness.y & 1u) == 0u)
    {
        InterlockedOr(nc_cert[2], 0x100u);
        return;
    }
    if (nc_cert[0] == 0u) rr_readiness[0u] = uint4(readiness.x, readiness.y | 2u, readiness.z, readiness.w);
}
