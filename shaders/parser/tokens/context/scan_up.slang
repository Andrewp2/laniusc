// Exclusive hierarchical max scan over token-context block events.

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

ConstantBuffer<Params> gContextScan;
StructuredBuffer<uint> statement_event_block;
RWStructuredBuffer<uint> statement_event_block_prefix;
RWStructuredBuffer<uint> statement_event_hierarchy;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared uint context_values[256];

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group_i = linear_group_id(gid);
    uint count = (gContextScan.n_blocks + gContextScan.level_divisor - 1u)
        / gContextScan.level_divisor;
    uint i = group_i * WG_SIZE + ltid.x;
    uint value = 0u;
    if (i < count)
    {
        value = gContextScan.level_divisor == 1u
            ? statement_event_block[i]
            : statement_event_hierarchy[gContextScan.level_offset + i];
    }

    prefix_scan_inclusive<uint, PrefixScanU32Max, 256>(
        ltid.x,
        value,
        context_values);
    uint inclusive = context_values[ltid.x];
    if (i < count)
    {
        if (gContextScan.level_divisor == 1u)
            statement_event_block_prefix[i] = ltid.x == 0u ? 0u : context_values[ltid.x - 1u];
        else
            statement_event_hierarchy[gContextScan.level_offset + i] = inclusive;
    }

    // `inclusive` is the complete group summary even for a partial final group,
    // because inactive lanes contribute the max identity.
    if (gContextScan.parent_divisor != 0u && ltid.x + 1u == WG_SIZE)
        statement_event_hierarchy[gContextScan.parent_offset + group_i] = inclusive;
}
