// Hierarchical inclusive scan of bracket block (sum, minimum-prefix) summaries.

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

ConstantBuffer<Params> gBracketScan;
StructuredBuffer<int> block_sum;
StructuredBuffer<int> block_minpref;
RWStructuredBuffer<int> prefix_sum;
RWStructuredBuffer<int> prefix_min;
RWStructuredBuffer<int> hierarchy_sum;
RWStructuredBuffer<int> hierarchy_min;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared int2 scan_values[256];

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

int2 load_summary(uint i)
{
    if (gBracketScan.level_divisor == 1u)
        return int2(block_sum[i], block_minpref[i]);
    uint row = gBracketScan.level_offset + i;
    return int2(hierarchy_sum[row], hierarchy_min[row]);
}

void store_summary(uint row, int2 summary)
{
    hierarchy_sum[row] = summary.x;
    hierarchy_min[row] = summary.y;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group_i = linear_group_id(gid);
    uint count = (gBracketScan.n_blocks + gBracketScan.level_divisor - 1u)
        / gBracketScan.level_divisor;
    uint i = group_i * WG_SIZE + ltid.x;
    int2 summary = i < count
        ? load_summary(i)
        : PrefixScanI32x2SumMinPrefix.identity();
    prefix_scan_inclusive<int2, PrefixScanI32x2SumMinPrefix, 256>(
        ltid.x,
        summary,
        scan_values);
    int2 inclusive = scan_values[ltid.x];
    if (i < count)
    {
        if (gBracketScan.level_divisor == 1u)
        {
            prefix_sum[i] = inclusive.x;
            prefix_min[i] = inclusive.y;
        }
        else
            store_summary(gBracketScan.level_offset + i, inclusive);
    }
    if (gBracketScan.parent_divisor != 0u && ltid.x + 1u == WG_SIZE)
        store_summary(gBracketScan.parent_offset + group_i, inclusive);
}
