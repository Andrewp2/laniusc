// Pointer-jump dense semantic-HIR previous-sibling links to compute child_idx.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> ll1_status;
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

    uint link = hir_semantic_child_index_link_in[row];
    uint rank = hir_semantic_child_index_rank_in[row];
    if (!valid_semantic_row(link, semantic_count) || link == row)
    {
        hir_semantic_child_index_link_out[row] = INVALID;
        hir_semantic_child_index_rank_out[row] = rank;
        return;
    }

    hir_semantic_child_index_rank_out[row] =
        rank + hir_semantic_child_index_rank_in[link];
    uint next_link = hir_semantic_child_index_link_in[link];
    hir_semantic_child_index_link_out[row] =
        valid_semantic_row(next_link, semantic_count) ? next_link : INVALID;
}
