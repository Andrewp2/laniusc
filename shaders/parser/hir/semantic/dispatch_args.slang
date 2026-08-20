// Build indirect dispatch arguments for dense semantic-HIR passes.
//
// The parser first compactifies semantic HIR nodes with a prefix scan. Passes
// that only need semantic HIR rows can then dispatch over the dense row count
// rather than over every emitted parse-tree production.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemanticDispatch;

StructuredBuffer<uint> hir_semantic_count;
RWStructuredBuffer<uint> hir_semantic_dispatch_args;
StructuredBuffer<uint> hir_raw_relation_dispatch_args;
RWStructuredBuffer<uint> hir_semantic_relation_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LINKS_PER_RELATION_STEP = 16u;

uint relation_step_capacity(uint items)
{
    uint steps = 0u;
    uint reach = 1u;
    while (steps < 8u && reach < max(1u, items))
    {
        steps += 1u;
        reach *= LINKS_PER_RELATION_STEP;
    }
    return steps;
}

void write_dispatch_args(uint active_records)
{
    uint groups = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
    uint groups_x = min(groups, MAX_GROUPS_X);
    uint groups_y = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    hir_semantic_dispatch_args[0u] = groups_x;
    hir_semantic_dispatch_args[1u] = groups_y;
    hir_semantic_dispatch_args[2u] = 1u;

    // Every dense semantic-parent edge represents one or more raw-tree parent
    // edges, so semantic depth cannot exceed raw depth. Reuse the raw schedule's
    // active-round mask while preserving the compact semantic dispatch geometry.
    uint steps = relation_step_capacity(gHirSemanticDispatch.n);
    for (uint step = 0u; step < steps; step += 1u)
    {
        uint out = step * 3u;
        bool enabled = hir_raw_relation_dispatch_args[out] != 0u;
        hir_semantic_relation_dispatch_args[out + 0u] = enabled ? groups_x : 0u;
        hir_semantic_relation_dispatch_args[out + 1u] = enabled ? groups_y : 0u;
        hir_semantic_relation_dispatch_args[out + 2u] = enabled ? 1u : 0u;
    }
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    write_dispatch_args(min(hir_semantic_count[0u], gHirSemanticDispatch.n));
}
