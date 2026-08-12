// Hierarchical exclusive scan of delimiter depths and token-context events.

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

struct PrefixScanI32x4Add : IPrefixScanOp<int4>
{
    static int4 identity()
    {
        return int4(0, 0, 0, 0);
    }

    static int4 combine(int4 left, int4 right)
    {
        return left + right;
    }
};

struct PrefixScanU32x2Max : IPrefixScanOp<uint2>
{
    static uint2 identity()
    {
        return uint2(0u, 0u);
    }

    static uint2 combine(uint2 left, uint2 right)
    {
        return max(left, right);
    }
};

ConstantBuffer<Params> gDelimiterScan;
StructuredBuffer<int> block_sum_brace;
StructuredBuffer<int> block_sum_bracket;
StructuredBuffer<int> block_sum_paren;
StructuredBuffer<int> block_sum_angle;
StructuredBuffer<uint> top_brace_owner_block;
StructuredBuffer<uint> statement_event_block;

RWStructuredBuffer<int> block_prefix_brace;
RWStructuredBuffer<int> block_prefix_bracket;
RWStructuredBuffer<int> block_prefix_paren;
RWStructuredBuffer<int> block_prefix_angle;
RWStructuredBuffer<uint> top_brace_owner_block_prefix;
RWStructuredBuffer<uint> statement_event_block_prefix;

RWStructuredBuffer<int> hierarchy_brace;
RWStructuredBuffer<int> hierarchy_bracket;
RWStructuredBuffer<int> hierarchy_paren;
RWStructuredBuffer<int> hierarchy_angle;
RWStructuredBuffer<uint> hierarchy_owner;
RWStructuredBuffer<uint> hierarchy_event;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared int4 depth_scan_values[256];
groupshared uint2 event_scan_values[256];

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

int4 load_depth(uint i)
{
    if (gDelimiterScan.level_divisor == 1u)
        return int4(
            block_sum_brace[i], block_sum_bracket[i],
            block_sum_paren[i], block_sum_angle[i]);
    uint row = gDelimiterScan.level_offset + i;
    return int4(
        hierarchy_brace[row], hierarchy_bracket[row],
        hierarchy_paren[row], hierarchy_angle[row]);
}

uint2 load_event(uint i)
{
    if (gDelimiterScan.level_divisor == 1u)
        return uint2(top_brace_owner_block[i], statement_event_block[i]);
    uint row = gDelimiterScan.level_offset + i;
    return uint2(hierarchy_owner[row], hierarchy_event[row]);
}

void store_hierarchy(uint row, int4 depth, uint2 event)
{
    hierarchy_brace[row] = depth.x;
    hierarchy_bracket[row] = depth.y;
    hierarchy_paren[row] = depth.z;
    hierarchy_angle[row] = depth.w;
    hierarchy_owner[row] = event.x;
    hierarchy_event[row] = event.y;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group_i = linear_group_id(gid);
    uint count = (gDelimiterScan.n_blocks + gDelimiterScan.level_divisor - 1u)
        / gDelimiterScan.level_divisor;
    uint i = group_i * WG_SIZE + ltid.x;
    int4 depth = i < count ? load_depth(i) : PrefixScanI32x4Add.identity();
    uint2 event = i < count ? load_event(i) : PrefixScanU32x2Max.identity();
    prefix_scan_inclusive<int4, PrefixScanI32x4Add, 256>(
        ltid.x,
        depth,
        depth_scan_values);
    int4 inclusive_depth = depth_scan_values[ltid.x];
    prefix_scan_inclusive<uint2, PrefixScanU32x2Max, 256>(
        ltid.x,
        event,
        event_scan_values);
    uint2 inclusive_event = event_scan_values[ltid.x];
    if (i < count)
    {
        if (gDelimiterScan.level_divisor == 1u)
        {
            int4 exclusive_depth = ltid.x == 0u
                ? PrefixScanI32x4Add.identity()
                : depth_scan_values[ltid.x - 1u];
            uint2 exclusive_event = ltid.x == 0u
                ? PrefixScanU32x2Max.identity()
                : event_scan_values[ltid.x - 1u];
            block_prefix_brace[i] = exclusive_depth.x;
            block_prefix_bracket[i] = exclusive_depth.y;
            block_prefix_paren[i] = exclusive_depth.z;
            block_prefix_angle[i] = exclusive_depth.w;
            top_brace_owner_block_prefix[i] = exclusive_event.x;
            statement_event_block_prefix[i] = exclusive_event.y;
        }
        else
            store_hierarchy(
                gDelimiterScan.level_offset + i,
                inclusive_depth,
                inclusive_event);
    }
    if (gDelimiterScan.parent_divisor != 0u && ltid.x + 1u == WG_SIZE)
        store_hierarchy(
            gDelimiterScan.parent_offset + group_i,
            inclusive_depth,
            inclusive_event);
}
