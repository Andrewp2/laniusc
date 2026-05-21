// Seed dense semantic-HIR depth pointer jumping.
//
// Pareas represents backend trees with a node depth field and schedules
// instruction generation bottom-up by depth. This pass initializes logarithmic
// depth accumulation over dense semantic parent rows.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> ll1_status;
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
    return gHirSemantic.uses_ll1 != 0u ? min(gHirSemantic.n, ll1_status[5u]) : gHirSemantic.n;
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

    uint parent = hir_semantic_parent[row];
    bool has_parent = valid_semantic_row(parent, semantic_count);
    hir_semantic_depth_link_a[row] = has_parent ? parent : INVALID;
    hir_semantic_depth_value_a[row] = has_parent ? 1u : 0u;
}
