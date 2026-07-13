// Build a pointer-jump dispatch schedule from the actual semantic-tree height.
// Slots after ceil(log2(max_depth + 1)) are zero dispatches, so host command
// recording remains capacity-stable without executing redundant global rounds.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> hir_semantic_dispatch_args;
StructuredBuffer<uint> hir_semantic_depth_block_max;
RWStructuredBuffer<uint> hir_semantic_pointer_jump_dispatch_args;

static const uint WG_SIZE = 256u;

groupshared uint lane_max_depth[WG_SIZE];

uint pointer_jump_step_capacity(uint items)
{
    uint steps = 0u;
    uint span = 1u;
    while (steps < 32u && span < items)
    {
        steps += 1u;
        span <<= 1u;
    }
    return steps;
}

[shader("compute")]
[numthreads(WG_SIZE, 1, 1)]
void main(uint3 gtid: SV_GroupThreadID)
{
    uint group_count = hir_semantic_dispatch_args[0u] * hir_semantic_dispatch_args[1u];
    uint lane_depth = 0u;
    for (uint group = gtid.x; group < group_count; group += WG_SIZE)
        lane_depth = max(lane_depth, hir_semantic_depth_block_max[group]);
    lane_max_depth[gtid.x] = lane_depth;
    GroupMemoryBarrierWithGroupSync();

    for (uint stride = WG_SIZE / 2u; stride != 0u; stride >>= 1u)
    {
        if (gtid.x < stride)
            lane_max_depth[gtid.x] =
                max(lane_max_depth[gtid.x], lane_max_depth[gtid.x + stride]);
        GroupMemoryBarrierWithGroupSync();
    }

    uint required_steps = pointer_jump_step_capacity(lane_max_depth[0u] + 1u);
    uint step_capacity = pointer_jump_step_capacity(gHirSemantic.n);
    // The host's final canonicalization is based on capacity parity. If the
    // real height has the other parity, one final active round copies the
    // converged values through the ping-pong buffers before canonicalization.
    uint scheduled_steps = required_steps + ((required_steps ^ step_capacity) & 1u);
    for (uint step = gtid.x; step < step_capacity; step += WG_SIZE)
    {
        uint output = step * 3u;
        bool enabled = step < scheduled_steps;
        hir_semantic_pointer_jump_dispatch_args[output + 0u] =
            enabled ? hir_semantic_dispatch_args[0u] : 0u;
        hir_semantic_pointer_jump_dispatch_args[output + 1u] =
            enabled ? hir_semantic_dispatch_args[1u] : 0u;
        hir_semantic_pointer_jump_dispatch_args[output + 2u] =
            enabled ? hir_semantic_dispatch_args[2u] : 0u;
    }
}
