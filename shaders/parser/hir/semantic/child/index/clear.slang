// Clear dense semantic-HIR child-index scratch.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;

RWStructuredBuffer<uint> hir_semantic_child_index_link_a;
RWStructuredBuffer<uint> hir_semantic_child_index_rank_a;
RWStructuredBuffer<uint> hir_semantic_child_index;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_semantic_count())
        return;

    hir_semantic_child_index_link_a[row] = INVALID;
    hir_semantic_child_index_rank_a[row] = 0u;
    hir_semantic_child_index[row] = 0u;
}
