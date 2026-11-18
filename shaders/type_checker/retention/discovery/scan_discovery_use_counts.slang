import type_checker.retention.discovery.discovery_workspace;
// Exclusive placement of each frontier instance's uses: a block scan in
// three dispatches (mode 3, 4, 2) for any frontier width.
groupshared uint dg_scan_shared[256];
// Inclusive scan of `value` across the workgroup. Every lane must call it.
uint dg_block_inclusive(uint t, uint value)
{
    dg_scan_shared[t] = value;
    GroupMemoryBarrierWithGroupSync();
    for (uint d = 1u; d < 256u; d <<= 1u)
    {
        uint add = t >= d ? dg_scan_shared[t - d] : 0u;
        GroupMemoryBarrierWithGroupSync();
        dg_scan_shared[t] += add;
        GroupMemoryBarrierWithGroupSync();
    }
    return dg_scan_shared[t];
}
uint dg_uses_of(uint instance)
{
    uint decl = dg_instances[2u * instance].x;
    uint entry = dg_entry(decl);
    return entry == RT_INVALID ? 0u : rt_dir[entry * RT_DIR_WORDS + 3u].x;
}
[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 id: SV_DispatchThreadID, uint3 local: SV_GroupThreadID)
{
    uint lane = dg_lane(id); uint count = dg_config[2] - dg_config[1];
    uint t = local.x;
    if (dg_config[0] == 3u)
    {
        // Each block scans its lanes' use counts in shared memory.
        uint value = lane < count ? dg_uses_of(dg_config[1] + lane) : 0u;
        uint inclusive = dg_block_inclusive(t, value);
        if (lane < count) dg_scan_b[lane] = inclusive;
        if (t == 255u) dg_scan_blocks[lane / 256u] = inclusive;
        return;
    }
    if (dg_config[0] == 4u)
    {
        // One workgroup turns the block totals into exclusive prefixes.
        if (lane >= 256u) return;
        uint blocks = (count + 255u) / 256u;
        uint carry = 0u;
        for (uint base = 0u; base < blocks; base += 256u)
        {
            uint i = base + t;
            uint total = i < blocks ? dg_scan_blocks[i] : 0u;
            uint inclusive = dg_block_inclusive(t, total);
            if (i < blocks) dg_scan_blocks[i] = carry + inclusive - total;
            carry += dg_scan_shared[255u];
            GroupMemoryBarrierWithGroupSync();
        }
        return;
    }
    if (lane >= count) return;
    uint instance = dg_config[1] + lane;
    // Mode 2: the inclusive prefix is the block's plus the lane's. It goes
    // to dg_scan_a, which later passes read (config 9 = 0).
    uint end = dg_scan_b[lane] + dg_scan_blocks[lane / 256u];
    uint start = end - dg_uses_of(instance);
    dg_scan_a[lane] = end;
    uint4 old = dg_instances[2u * instance + 1u];
    dg_instances[2u * instance + 1u] = uint4(dg_config[3] + start,end-start,old.z,0u);
    if (lane + 1u == count)
    {
        uint demand = dg_config[3] + end;
        dg_status[2] = demand; dg_status[5] = demand;
        uint capacity; uint stride; dg_edges.GetDimensions(capacity,stride);
        if (demand > capacity) InterlockedOr(dg_status[3],2u);
        // The request pass runs one lane per edge, or none after an
        // overflow (the host grows and repeats the attempt).
        uint groups = demand > capacity ? 0u : (end + 255u) / 256u;
        dg_indirect[0] = min(groups, 65535u);
        dg_indirect[1] = groups == 0u ? 0u : (groups + 65534u) / 65535u;
        dg_indirect[2] = 1u;
    }
}
