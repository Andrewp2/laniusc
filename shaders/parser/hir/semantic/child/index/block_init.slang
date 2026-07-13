// Compress bounded previous-sibling blocks before global pointer jumping.

struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_child_index_link_in;
StructuredBuffer<uint> hir_semantic_child_index_rank_in;

RWStructuredBuffer<uint> hir_semantic_child_index_link_out;
RWStructuredBuffer<uint> hir_semantic_child_index_rank_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirSemantic.uses_status_count != 0u
               ? min(gHirSemantic.n, tree_count_status[5u])
               : gHirSemantic.n;
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

    uint link = hir_semantic_child_index_link_in[row];
    uint rank = hir_semantic_child_index_rank_in[row];
    uint local_span = max(1u, gHirSemantic.semantic_parent_local_ancestor_span);
    for (uint hop = 1u; hop < local_span && valid_semantic_row(link, semantic_count); ++hop)
    {
        uint next = hir_semantic_child_index_link_in[link];
        rank += hir_semantic_child_index_rank_in[link];
        link = valid_semantic_row(next, semantic_count) ? next : INVALID;
    }

    hir_semantic_child_index_link_out[row] = link;
    hir_semantic_child_index_rank_out[row] = rank;
}
