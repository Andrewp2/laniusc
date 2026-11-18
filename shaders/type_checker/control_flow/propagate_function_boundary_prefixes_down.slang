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

RWStructuredBuffer<uint> block_prefix;
RWStructuredBuffer<uint> scan_prefix;
RWStructuredBuffer<uint> scan_hierarchy;

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
    uint count = (gHierarchy.n_blocks + gHierarchy.level_divisor - 1u) /
        gHierarchy.level_divisor;
    if (i >= count)
        return;
    uint group_i = i / WG_SIZE;
    uint carry = group_i == 0u ? 0u : scan_hierarchy[gHierarchy.parent_offset + group_i - 1u];
    if (gHierarchy.level_divisor == 1u)
    {
        uint lane = i % WG_SIZE;
        block_prefix[i] = lane == 0u ? carry : max(scan_prefix[i - 1u], carry);
    }
    else
    {
        scan_hierarchy[gHierarchy.level_offset + i] =
            max(scan_hierarchy[gHierarchy.level_offset + i], carry);
    }
}
