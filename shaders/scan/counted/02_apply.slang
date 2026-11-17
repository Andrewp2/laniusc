// Apply of a GPU-counted u32 exclusive scan: adds each block's carry to the
// local prefixes and writes the total. The carry is the sum of the earlier
// blocks' sums (block_carry.slang); workgroup 0 sums every block for the
// total.

import scan.block_carry;

struct Params
{
    uint n_items;
    uint n_blocks;
    uint min_items;
};

ConstantBuffer<Params> gScan;

StructuredBuffer<uint> scan_count;
StructuredBuffer<uint> scan_local_prefix;
StructuredBuffer<uint> scan_block_sum;
RWStructuredBuffer<uint> scan_output_prefix;
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
        carry = 0u;
    }
    uint i = block_i * WG_SIZE + ltid.x;
    if (i < count)
        scan_output_prefix[i] = carry + scan_local_prefix[i];
}
