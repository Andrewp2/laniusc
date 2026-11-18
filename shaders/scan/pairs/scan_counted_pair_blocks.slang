// Two independent counted exclusive scans evaluated as one uint2 scan.

import prefix_scan;

struct Params
{
    uint n_items;
    uint n_blocks;
    uint min_items;
};

ConstantBuffer<Params> gScan;

StructuredBuffer<uint> scan_count;
StructuredBuffer<uint> scan_input_left;
StructuredBuffer<uint> scan_input_right;
RWStructuredBuffer<uint> scan_output_prefix_left;
RWStructuredBuffer<uint> scan_output_prefix_right;
RWStructuredBuffer<uint> scan_block_sum_left;
RWStructuredBuffer<uint> scan_block_sum_right;

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
    uint2 value = i < count
        ? uint2(scan_input_left[i], scan_input_right[i])
        : uint2(0u, 0u);
    uint2 inclusive = prefix_scan_u32x2_256(ltid.x, value);

    if (i < count)
    {
        uint2 exclusive = inclusive - value;
        scan_output_prefix_left[i] = exclusive.x;
        scan_output_prefix_right[i] = exclusive.y;
    }
    if (ltid.x == WG_SIZE - 1u)
    {
        scan_block_sum_left[block_i] = inclusive.x;
        scan_block_sum_right[block_i] = inclusive.y;
    }
}
