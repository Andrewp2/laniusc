// Build capacity-stable pointer-jump commands from actual raw parse-tree depth.
struct Params { uint n; uint uses_status_count; uint n_prefix_blocks; uint max_tree_leaf_base; };
ConstantBuffer<Params> gTree;
struct CanonicalParams { uint raw_capacity; uint canonical_capacity; uint uses_status_count; uint local_ancestor_span; uint records_use_token_rows; };
ConstantBuffer<CanonicalParams> gCanonical;
struct HirParams { uint n; uint uses_status_count; uint semantic_parent_local_ancestor_span; uint retain_debug_rows; uint parser_feature_flags; };
ConstantBuffer<HirParams> gHir;
StructuredBuffer<uint> tree_active_dispatch_args;
StructuredBuffer<uint> tree_depth_block_max;
RWStructuredBuffer<uint> hir_raw_relation_dispatch_args;
RWStructuredBuffer<uint> hir_local_relation_dispatch_args;

static const uint WG_SIZE = 256u;
groupshared uint lane_max_depth[WG_SIZE];

uint step_capacity(uint items)
{
    uint steps = 0u;
    uint span = 1u;
    while (steps < 8u && span < items) { steps += 1u; span *= 16u; }
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

    uint raw_span = max(1u, gCanonical.local_ancestor_span);
    uint raw_required_steps = step_capacity(
        (lane_max_depth[0u] + 1u + raw_span - 1u) / raw_span);
    uint raw_capacity = step_capacity((gTree.n + raw_span - 1u) / raw_span);
    uint raw_scheduled_steps = raw_required_steps +
        ((raw_required_steps ^ raw_capacity) & 1u);
    for (uint step = lane.x; step < raw_capacity; step += WG_SIZE)
    {
        uint out = step * 3u;
        bool enabled = step < raw_scheduled_steps;
        hir_raw_relation_dispatch_args[out + 0u] =
            enabled ? tree_active_dispatch_args[0u] : 0u;
        hir_raw_relation_dispatch_args[out + 1u] =
            enabled ? tree_active_dispatch_args[1u] : 0u;
        hir_raw_relation_dispatch_args[out + 2u] =
            enabled ? tree_active_dispatch_args[2u] : 0u;
    }

    uint local_span = max(1u, gHir.semantic_parent_local_ancestor_span);
    uint local_required_steps = step_capacity(
        (lane_max_depth[0u] + 1u + local_span - 1u) / local_span);
    uint local_capacity = step_capacity((gTree.n + local_span - 1u) / local_span);
    uint local_scheduled_steps = local_required_steps +
        ((local_required_steps ^ local_capacity) & 1u);
    for (uint step = lane.x; step < local_capacity; step += WG_SIZE)
    {
        uint out = step * 3u;
        bool enabled = step < local_scheduled_steps;
        hir_local_relation_dispatch_args[out + 0u] =
            enabled ? tree_active_dispatch_args[0u] : 0u;
        hir_local_relation_dispatch_args[out + 1u] =
            enabled ? tree_active_dispatch_args[1u] : 0u;
        hir_local_relation_dispatch_args[out + 2u] =
            enabled ? tree_active_dispatch_args[2u] : 0u;
    }
}
