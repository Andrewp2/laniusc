// Propagates hierarchical carries through bracket block summaries.

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
RWStructuredBuffer<int> prefix_sum;
RWStructuredBuffer<int> prefix_min;
RWStructuredBuffer<int> hierarchy_sum;
RWStructuredBuffer<int> hierarchy_min;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint count = (gBracketScan.n_blocks + gBracketScan.level_divisor - 1u)
        / gBracketScan.level_divisor;
    if (i >= count)
        return;

    uint group_i = i / WG_SIZE;
    int2 carry = PrefixScanI32x2SumMinPrefix.identity();
    if (group_i != 0u)
    {
        uint carry_row = gBracketScan.parent_offset + group_i - 1u;
        carry = int2(hierarchy_sum[carry_row], hierarchy_min[carry_row]);
    }

    if (gBracketScan.level_divisor == 1u)
    {
        int2 current = int2(prefix_sum[i], prefix_min[i]);
        int2 combined = PrefixScanI32x2SumMinPrefix.combine(carry, current);
        prefix_sum[i] = combined.x;
        prefix_min[i] = combined.y;
    }
    else
    {
        uint row = gBracketScan.level_offset + i;
        int2 current = int2(hierarchy_sum[row], hierarchy_min[row]);
        int2 combined = PrefixScanI32x2SumMinPrefix.combine(carry, current);
        hierarchy_sum[row] = combined.x;
        hierarchy_min[row] = combined.y;
    }
}
