// Inclusive 256-way upsweep over precomputed block sums.

import prefix_scan;

struct Params
{
    uint n_blocks;
    uint level_divisor;
    uint level_offset;
    uint parent_divisor;
    uint parent_offset;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gBlockScan;
StructuredBuffer<uint> block_sum;
RWStructuredBuffer<uint> block_prefix;
RWStructuredBuffer<uint> block_hierarchy;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group_i = linear_group_id(gid);
    uint count = (gBlockScan.n_blocks + gBlockScan.level_divisor - 1u)
        / gBlockScan.level_divisor;
    uint i = group_i * WG_SIZE + ltid.x;
    uint value = 0u;
    if (i < count)
    {
        value = gBlockScan.level_divisor == 1u
            ? block_sum[i]
            : block_hierarchy[gBlockScan.level_offset + i];
    }

    uint inclusive = prefix_scan_u32_256(ltid.x, value);
    if (i < count)
    {
        if (gBlockScan.level_divisor == 1u)
            block_prefix[i] = inclusive;
        else
            block_hierarchy[gBlockScan.level_offset + i] = inclusive;
    }

    if (gBlockScan.parent_divisor != 0u && ltid.x + 1u == WG_SIZE)
        block_hierarchy[gBlockScan.parent_offset + group_i] = inclusive;
}
