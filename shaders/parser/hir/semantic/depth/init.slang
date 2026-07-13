// Seed dense semantic-HIR depth pointer jumping.
//
// Pareas represents backend trees with a node depth field and schedules
// instruction generation bottom-up by depth. This pass initializes logarithmic
// depth accumulation over dense semantic parent rows.

struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_parent;

RWStructuredBuffer<uint> hir_semantic_depth_link_a;
RWStructuredBuffer<uint> hir_semantic_depth_value_a;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirSemantic.uses_status_count != 0u ? min(gHirSemantic.n, tree_count_status[5u]) : gHirSemantic.n;
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

bool valid_semantic_row(uint row, uint semantic_count)
{
    return row != INVALID && row < semantic_count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint semantic_count = active_semantic_count();
    if (row >= semantic_count)
        return;

    uint ancestor = hir_semantic_parent[row];
    uint depth = 0u;
    uint local_span = max(1u, gHirSemantic.semantic_parent_local_ancestor_span);
    for (uint hop = 0u; hop < local_span; ++hop)
    {
        if (!valid_semantic_row(ancestor, semantic_count))
            break;
        depth += 1u;
        if (hop + 1u == local_span)
        {
            hir_semantic_depth_link_a[row] = ancestor;
            hir_semantic_depth_value_a[row] = depth;
            return;
        }
        ancestor = hir_semantic_parent[ancestor];
    }
    hir_semantic_depth_link_a[row] = INVALID;
    hir_semantic_depth_value_a[row] = depth;
}
