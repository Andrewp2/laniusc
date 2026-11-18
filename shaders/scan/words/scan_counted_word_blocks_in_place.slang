// First stage of an in-place counted exclusive u32 scan.

import prefix_scan;

struct Params
{
    uint n_items;
    uint n_blocks;
    uint min_items;
};

ConstantBuffer<Params> gScan;

StructuredBuffer<uint> scan_count;
RWStructuredBuffer<uint> scan_values;
RWStructuredBuffer<uint> scan_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_items()
{
    return min(max(scan_count[0], gScan.min_items), gScan.n_items);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = gid.x + gid.y * MAX_GROUPS_X;
    uint count = active_items();
    if (block_i >= (count + WG_SIZE - 1u) / WG_SIZE)
        return;

    uint i = block_i * WG_SIZE + ltid.x;
    uint value = i < count ? scan_values[i] : 0u;
    uint inclusive = prefix_scan_u32_256(ltid.x, value);
    if (i < count)
        scan_values[i] = inclusive - value;
    if (ltid.x == WG_SIZE - 1u)
        scan_block_sum[block_i] = inclusive;
}
