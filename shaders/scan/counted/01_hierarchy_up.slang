// Parallel 256-way upsweep for GPU-counted u32 scans.

import prefix_scan;

struct Params
{
    uint n_items;
    uint n_blocks;
    uint level_divisor;
    uint level_offset;
    uint parent_divisor;
    uint parent_offset;
};

ConstantBuffer<Params> gHierarchy;

StructuredBuffer<uint> scan_count;
StructuredBuffer<uint> scan_block_sum;
RWStructuredBuffer<uint> scan_block_prefix;
RWStructuredBuffer<uint> scan_hierarchy;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_blocks()
{
    uint active_items = min(scan_count[0], gHierarchy.n_items);
    return (active_items + WG_SIZE - 1u) / WG_SIZE;
}

uint level_count()
{
    uint blocks = active_blocks();
    return (blocks + gHierarchy.level_divisor - 1u) / gHierarchy.level_divisor;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group_i = linear_group_id(gid);
    uint count = level_count();
    uint i = group_i * WG_SIZE + ltid.x;
    uint value = 0u;
    if (i < count)
    {
        value = gHierarchy.level_divisor == 1u
            ? scan_block_sum[i]
            : scan_hierarchy[gHierarchy.level_offset + i];
    }

    uint inclusive = prefix_scan_u32_256(ltid.x, value);
    if (i < count)
    {
        if (gHierarchy.level_divisor == 1u)
            scan_block_prefix[i] = inclusive;
        else
            scan_hierarchy[gHierarchy.level_offset + i] = inclusive;
    }

    if (gHierarchy.parent_divisor != 0u && ltid.x + 1u == WG_SIZE)
        scan_hierarchy[gHierarchy.parent_offset + group_i] = inclusive;
}
