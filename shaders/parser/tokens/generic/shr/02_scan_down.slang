// Carry propagation for contextual-`>>` stack-effect summaries.

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
RWStructuredBuffer<int> block_prefix_sum;
RWStructuredBuffer<int> block_prefix_min;
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
    uint count = (gGenericScan.n_blocks + gGenericScan.level_divisor - 1u)
        / gGenericScan.level_divisor;
    if (i >= count)
        return;

    uint group_i = i / WG_SIZE;
    int2 carry = group_i == 0u
        ? int2(0, 0)
        : int2(
            hierarchy_sum[gGenericScan.parent_offset + group_i - 1u],
            hierarchy_min[gGenericScan.parent_offset + group_i - 1u]);
    if (gGenericScan.level_divisor == 1u)
    {
        int2 local = int2(block_prefix_sum[i], block_prefix_min[i]);
        int2 value = PrefixScanI32x2SumMinPrefix.combine(carry, local);
        block_prefix_sum[i] = value.x;
        block_prefix_min[i] = value.y;
    }
    else
    {
        uint row = gGenericScan.level_offset + i;
        int2 local = int2(hierarchy_sum[row], hierarchy_min[row]);
        int2 value = PrefixScanI32x2SumMinPrefix.combine(carry, local);
        hierarchy_sum[row] = value.x;
        hierarchy_min[row] = value.y;
    }
}
