// Reduce dense semantic-HIR depth to one maximum per workgroup.

StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_depth;
RWStructuredBuffer<uint> hir_semantic_depth_block_max;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

groupshared uint block_depth[WG_SIZE];

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

[shader("compute")]
[numthreads(WG_SIZE, 1, 1)]
void main(
    uint3 dtid: SV_DispatchThreadID,
    uint3 gid: SV_GroupID,
    uint3 gtid: SV_GroupThreadID)
{
    uint row = linear_thread_id(dtid);
    uint semantic_count = hir_semantic_count[0u];
    block_depth[gtid.x] = row < semantic_count ? hir_semantic_depth[row] : 0u;
    GroupMemoryBarrierWithGroupSync();

    for (uint stride = WG_SIZE / 2u; stride != 0u; stride >>= 1u)
    {
        if (gtid.x < stride)
            block_depth[gtid.x] = max(block_depth[gtid.x], block_depth[gtid.x + stride]);
        GroupMemoryBarrierWithGroupSync();
    }

    if (gtid.x == 0u)
        hir_semantic_depth_block_max[linear_group_id(gid)] = block_depth[0u];
}
