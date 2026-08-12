// Hierarchical exclusive scan of contextual-`>>` stack-effect summaries.

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

ConstantBuffer<Params> gGenericScan;
StructuredBuffer<int> block_sum;
StructuredBuffer<int> block_min;
RWStructuredBuffer<int> block_prefix_sum;
RWStructuredBuffer<int> block_prefix_min;
RWStructuredBuffer<int> hierarchy_sum;
RWStructuredBuffer<int> hierarchy_min;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared int2 scan_values[256];

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group_i = linear_group_id(gid);
    uint count = (gGenericScan.n_blocks + gGenericScan.level_divisor - 1u)
        / gGenericScan.level_divisor;
    uint i = group_i * WG_SIZE + ltid.x;
    int2 value = int2(0, 0);
    if (i < count)
    {
        value = gGenericScan.level_divisor == 1u
            ? int2(block_sum[i], block_min[i])
            : int2(
                hierarchy_sum[gGenericScan.level_offset + i],
                hierarchy_min[gGenericScan.level_offset + i]);
    }

    prefix_scan_inclusive<int2, PrefixScanI32x2SumMinPrefix, 256>(
        ltid.x,
        value,
        scan_values);
    int2 inclusive = scan_values[ltid.x];
    if (i < count)
    {
        if (gGenericScan.level_divisor == 1u)
        {
            int2 exclusive = ltid.x == 0u ? int2(0, 0) : scan_values[ltid.x - 1u];
            block_prefix_sum[i] = exclusive.x;
            block_prefix_min[i] = exclusive.y;
        }
        else
        {
            hierarchy_sum[gGenericScan.level_offset + i] = inclusive.x;
            hierarchy_min[gGenericScan.level_offset + i] = inclusive.y;
        }
    }

    if (gGenericScan.parent_divisor != 0u && ltid.x + 1u == WG_SIZE)
    {
        hierarchy_sum[gGenericScan.parent_offset + group_i] = inclusive.x;
        hierarchy_min[gGenericScan.parent_offset + group_i] = inclusive.y;
    }
}
