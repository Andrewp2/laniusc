// Inclusive scan of the plan's counts in ps_scan_a, in three dispatches for
// any round width: mode 0 scans each block of 256 lanes, mode 1 (one
// workgroup) turns the block totals into exclusive prefixes, mode 2 adds
// them. Modes 0 and 2 run on the round's term-lane dispatch.
import type_checker.retention.projection.schema.common;
import type_checker.retention.projection.schema.round;
groupshared uint ps_shared[256];
uint ps_block_inclusive(uint t, uint value)
{
    ps_shared[t] = value;
    GroupMemoryBarrierWithGroupSync();
    for (uint d = 1u; d < 256u; d <<= 1u)
    {
        uint add = t >= d ? ps_shared[t - d] : 0u;
        GroupMemoryBarrierWithGroupSync();
        ps_shared[t] += add;
        GroupMemoryBarrierWithGroupSync();
    }
    return ps_shared[t];
}
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID, uint3 local: SV_GroupThreadID)
{
    uint lane = ps_lane(id);
    uint lanes = ps_round_terms() + 1u;
    uint t = local.x;
    uint mode = ps_config[PS_CFG_MODE];
    if (mode == 0u)
    {
        uint inclusive = ps_block_inclusive(t, lane < lanes ? ps_scan_a[lane] : 0u);
        if (lane < lanes) ps_scan_b[lane] = inclusive;
        if (t == 255u) ps_blocks[lane / 256u] = inclusive;
        return;
    }
    if (mode == 1u)
    {
        // Only an armed round has block totals of its own.
        if (lane >= 256u || ps_round[4] == 0u) return;
        uint blocks = (lanes + 255u) / 256u;
        uint carry = 0u;
        for (uint base = 0u; base < blocks; base += 256u)
        {
            uint i = base + t;
            uint total = i < blocks ? ps_blocks[i] : 0u;
            uint inclusive = ps_block_inclusive(t, total);
            if (i < blocks) ps_blocks[i] = carry + inclusive - total;
            uint sum = ps_shared[255u];
            if (t == 0u && sum > 0xffffffffu - carry) InterlockedOr(ps_status[PS_ERROR],2u);
            carry += sum;
            GroupMemoryBarrierWithGroupSync();
        }
        return;
    }
    if (lane >= lanes) return;
    ps_scan_a[lane] = ps_scan_b[lane] + ps_blocks[lane / 256u];
}
