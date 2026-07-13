// Build capacity-stable pointer-jump commands from actual raw parse-tree depth.
struct Params { uint n; uint uses_status_count; uint n_prefix_blocks; uint max_tree_leaf_base; };
ConstantBuffer<Params> gTree;
StructuredBuffer<uint> tree_active_dispatch_args;
StructuredBuffer<uint> tree_depth_block_max;
RWStructuredBuffer<uint> tree_pointer_jump_dispatch_args;

static const uint WG_SIZE = 256u;
groupshared uint lane_max_depth[WG_SIZE];

uint step_capacity(uint items)
{
    uint steps = 0u;
    uint span = 1u;
    while (steps < 32u && span < items) { steps += 1u; span <<= 1u; }
    return steps;
}

[shader("compute")]
[numthreads(WG_SIZE, 1, 1)]
void main(uint3 lane: SV_GroupThreadID)
{
    uint group_count = tree_active_dispatch_args[0u] * tree_active_dispatch_args[1u];
    uint local_max = 0u;
    for (uint group = lane.x; group < group_count; group += WG_SIZE)
        local_max = max(local_max, tree_depth_block_max[group]);
    lane_max_depth[lane.x] = local_max;
    GroupMemoryBarrierWithGroupSync();
    for (uint stride = WG_SIZE / 2u; stride != 0u; stride >>= 1u)
    {
        if (lane.x < stride) lane_max_depth[lane.x] = max(lane_max_depth[lane.x], lane_max_depth[lane.x + stride]);
        GroupMemoryBarrierWithGroupSync();
    }

    uint required_steps = step_capacity(lane_max_depth[0u] + 1u);
    uint capacity = step_capacity(gTree.n);
    uint scheduled_steps = required_steps + ((required_steps ^ capacity) & 1u);
    if (lane.x == 0u)
        tree_pointer_jump_dispatch_args[max(capacity, 1u) * 3u] = scheduled_steps;
    for (uint step = lane.x; step < capacity; step += WG_SIZE)
    {
        uint out = step * 3u;
        bool enabled = step < scheduled_steps;
        tree_pointer_jump_dispatch_args[out + 0u] = enabled ? tree_active_dispatch_args[0u] : 0u;
        tree_pointer_jump_dispatch_args[out + 1u] = enabled ? tree_active_dispatch_args[1u] : 0u;
        tree_pointer_jump_dispatch_args[out + 2u] = enabled ? tree_active_dispatch_args[2u] : 0u;
    }
}
