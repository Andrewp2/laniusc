// Apply of an in-place counted u32 exclusive scan: adds each block's carry
// (block_carry.slang) and writes the total from workgroup 0.

import scan.block_carry;

struct Params
{
    uint n_items;
    uint n_blocks;
    uint min_items;
};

ConstantBuffer<Params> gScan;

StructuredBuffer<uint> scan_count;
StructuredBuffer<uint> scan_block_sum;
RWStructuredBuffer<uint> scan_values;
RWStructuredBuffer<uint> scan_total;

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

    uint carry = block_carry_sum(ltid.x, block_i == 0u ? blocks : block_i, scan_block_sum);
    if (block_i == 0u)
    {
        if (ltid.x == 0u)
            scan_total[0] = carry;
        return;
    }
    uint i = block_i * WG_SIZE + ltid.x;
    if (i < count)
        scan_values[i] += carry;
}
