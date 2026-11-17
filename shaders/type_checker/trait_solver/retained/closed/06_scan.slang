import type_checker.trait_solver.retained.closed.common;
// Inclusive scan of the eight row counters per lane, as a block scan in
// three dispatches (cw_step mode 0, 1, 2) for any lane count. The result
// is in cw_scan_a (cw_config[7] = 0).
groupshared uint4 cw_scan_shared[2][256];
// Inclusive scan of (low, high) across the workgroup. Every lane calls it.
void cw_block_inclusive(uint t, inout uint4 low, inout uint4 high)
{
    cw_scan_shared[0][t] = low; cw_scan_shared[1][t] = high;
    GroupMemoryBarrierWithGroupSync();
    for (uint d = 1u; d < 256u; d <<= 1u)
    {
        uint4 a = t >= d ? cw_scan_shared[0][t - d] : uint4(0u, 0u, 0u, 0u);
        uint4 b = t >= d ? cw_scan_shared[1][t - d] : uint4(0u, 0u, 0u, 0u);
        GroupMemoryBarrierWithGroupSync();
        cw_scan_shared[0][t] += a; cw_scan_shared[1][t] += b;
        GroupMemoryBarrierWithGroupSync();
    }
    low = cw_scan_shared[0][t]; high = cw_scan_shared[1][t];
}
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id:SV_DispatchThreadID, uint3 local:SV_GroupThreadID)
{
    uint i=cw_lane(id); uint t=local.x; uint lanes=cw_lanes();
    uint4 zero=uint4(0u,0u,0u,0u);
    uint mode=cw_step[0].x;
    if (mode==0u)
    {
        // Block-local scans; the block's totals go to cw_blocks.
        uint4 low=i<lanes ? cw_scan_a[2u*i] : zero;
        uint4 high=i<lanes ? cw_scan_a[2u*i+1u] : zero;
        cw_block_inclusive(t,low,high);
        if (i<lanes) { cw_scan_b[2u*i]=low; cw_scan_b[2u*i+1u]=high; }
        if (t==255u) { cw_blocks[2u*(i/256u)]=low; cw_blocks[2u*(i/256u)+1u]=high; }
    }
    else if (mode==1u)
    {
        // The first workgroup turns the totals into exclusive prefixes.
        if (i>=256u) return;
        uint blocks=(lanes+255u)/256u;
        uint4 carry_low=zero; uint4 carry_high=zero;
        for (uint base=0u;base<blocks;base+=256u)
        {
            uint b=base+t;
            uint4 low=b<blocks ? cw_blocks[2u*b] : zero;
            uint4 high=b<blocks ? cw_blocks[2u*b+1u] : zero;
            uint4 total_low=low; uint4 total_high=high;
            cw_block_inclusive(t,low,high);
            if (b<blocks) { cw_blocks[2u*b]=carry_low+low-total_low; cw_blocks[2u*b+1u]=carry_high+high-total_high; }
            carry_low+=cw_scan_shared[0][255u]; carry_high+=cw_scan_shared[1][255u];
            GroupMemoryBarrierWithGroupSync();
        }
    }
    else if (i<lanes)
    {
        uint b=i/256u;
        cw_scan_a[2u*i]=cw_scan_b[2u*i]+cw_blocks[2u*b];
        cw_scan_a[2u*i+1u]=cw_scan_b[2u*i+1u]+cw_blocks[2u*b+1u];
    }
}
