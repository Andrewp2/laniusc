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

StructuredBuffer<int> block_sum;
RWStructuredBuffer<int> block_prefix;
RWStructuredBuffer<int> scan_prefix;
RWStructuredBuffer<int> scan_hierarchy;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared int top_prefix[WG_SIZE];

uint linear_group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group_i = linear_group_id(gid);
    uint count = (gHierarchy.n_blocks + gHierarchy.level_divisor - 1u) /
        gHierarchy.level_divisor;
    uint i = group_i * WG_SIZE + ltid.x;
    int value = i < count
        ? (gHierarchy.level_divisor == 1u
            ? block_sum[i]
            : scan_hierarchy[gHierarchy.level_offset + i])
        : 0;
    int inclusive = prefix_scan_i32_256(ltid.x, value);

    if (i < count)
    {
        if (gHierarchy.level_divisor == 1u)
            scan_prefix[i] = inclusive;
        else
            scan_hierarchy[gHierarchy.level_offset + i] = inclusive;
    }
    if (gHierarchy.parent_divisor != 0u && ltid.x + 1u == WG_SIZE)
        scan_hierarchy[gHierarchy.parent_offset + group_i] = inclusive;

    if (gHierarchy.parent_divisor == 0u && gHierarchy.level_divisor == 1u)
    {
        top_prefix[ltid.x] = inclusive;
        GroupMemoryBarrierWithGroupSync();
        if (i < count)
            block_prefix[i] = ltid.x == 0u ? 0 : top_prefix[ltid.x - 1u];
    }
}
