// Reusable u32 exclusive prefix scan whose active item count is GPU-produced.
//
// This is for compact tables whose logical row count is stored in a GPU buffer.
// It preserves the host-side scheduling shape of the regular scan while letting
// the shader ignore inactive capacity rows without CPU readback.

import prefix_scan;

struct Params
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gScan;

StructuredBuffer<uint> scan_count;
StructuredBuffer<uint> scan_input;
RWStructuredBuffer<uint> scan_local_prefix;
RWStructuredBuffer<uint> scan_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_items()
{
    return min(scan_count[0], gScan.n_items);
}

uint active_blocks()
{
    return (active_items() + WG_SIZE - 1u) / WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    if (block_i >= active_blocks())
        return;

    uint lane = ltid.x;
    uint i = block_i * WG_SIZE + lane;
    uint value = i < active_items() ? scan_input[i] : 0u;
    uint inclusive = prefix_scan_u32_256(lane, value);

    if (i < active_items())
        scan_local_prefix[i] = inclusive - value;

    if (lane == WG_SIZE - 1u)
        scan_block_sum[block_i] = inclusive;
}
