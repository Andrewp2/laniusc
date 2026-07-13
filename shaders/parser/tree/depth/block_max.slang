struct Params { uint n; uint uses_status_count; uint n_prefix_blocks; uint max_tree_leaf_base; };
ConstantBuffer<Params> gTree;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> tree_depth;
RWStructuredBuffer<uint> tree_depth_block_max;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared uint block_depth[WG_SIZE];
uint linear_thread_id(uint3 tid) { return tid.x + tid.y * MAX_GROUPS_X * WG_SIZE; }
uint linear_group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
uint active_node_count() { return gTree.uses_status_count != 0u ? min(gTree.n, tree_count_status[5u]) : gTree.n; }

[shader("compute")]
[numthreads(WG_SIZE, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID, uint3 gid: SV_GroupID, uint3 lane: SV_GroupThreadID)
{
    uint node = linear_thread_id(tid);
    uint active = active_node_count();
    block_depth[lane.x] = node < active ? tree_depth[node] : 0u;
    GroupMemoryBarrierWithGroupSync();
    for (uint stride = WG_SIZE / 2u; stride != 0u; stride >>= 1u)
    {
        if (lane.x < stride) block_depth[lane.x] = max(block_depth[lane.x], block_depth[lane.x + stride]);
        GroupMemoryBarrierWithGroupSync();
    }
    if (lane.x == 0u) tree_depth_block_max[linear_group_id(gid)] = block_depth[0u];
}
