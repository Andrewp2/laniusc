// Logarithmic dense semantic-HIR depth accumulation.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_depth_link_in;
StructuredBuffer<uint> hir_semantic_depth_value_in;

RWStructuredBuffer<uint> hir_semantic_depth_link_out;
RWStructuredBuffer<uint> hir_semantic_depth_value_out;

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

    uint link = hir_semantic_depth_link_in[row];
    uint depth = hir_semantic_depth_value_in[row];
    if (!valid_semantic_row(link, semantic_count) || link == row)
    {
        hir_semantic_depth_link_out[row] = INVALID;
        hir_semantic_depth_value_out[row] = depth;
        return;
    }

    hir_semantic_depth_value_out[row] = depth + hir_semantic_depth_value_in[link];
    uint next_link = hir_semantic_depth_link_in[link];
    hir_semantic_depth_link_out[row] = valid_semantic_row(next_link, semantic_count)
        ? next_link
        : INVALID;
}
