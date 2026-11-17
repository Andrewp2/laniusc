// Apply of two independent counted scans (block_carry.slang): adds each
// block's carries to the local prefixes, which the local pass wrote into
// the outputs, and writes both totals from workgroup 0.

import scan.block_carry;

struct Params
{
    uint n_items;
    uint n_blocks;
    uint min_items;
};

ConstantBuffer<Params> gScan;

StructuredBuffer<uint> scan_count;
StructuredBuffer<uint> scan_block_sum_left;
StructuredBuffer<uint> scan_block_sum_right;
RWStructuredBuffer<uint> scan_output_prefix_left;
RWStructuredBuffer<uint> scan_output_prefix_right;
RWStructuredBuffer<uint> scan_total_left;
RWStructuredBuffer<uint> scan_total_right;

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
    uint blocks = (count + WG_SIZE - 1u) / WG_SIZE;
    if (block_i != 0u && block_i >= blocks)
        return;

    uint2 carry = block_carry_sum2(
        ltid.x, block_i == 0u ? blocks : block_i, scan_block_sum_left, scan_block_sum_right);
    if (block_i == 0u)
    {
        if (ltid.x == 0u)
        {
            scan_total_left[0] = carry.x;
            scan_total_right[0] = carry.y;
        }
        return;
    }
    uint i = block_i * WG_SIZE + ltid.x;
    if (i < count)
    {
        scan_output_prefix_left[i] += carry.x;
        scan_output_prefix_right[i] += carry.y;
    }
}
