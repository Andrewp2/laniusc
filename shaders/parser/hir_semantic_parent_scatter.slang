// Project nearest semantic parents into dense semantic-HIR row space.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirSemantic;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_parent_value;

RWStructuredBuffer<uint> hir_semantic_parent;

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

bool valid_original_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

bool valid_semantic_row(uint row)
{
    return row != INVALID && row < active_semantic_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint semantic_count = active_semantic_count();
    if (row >= semantic_count)
        return;

    uint original_node = hir_semantic_dense_node[row];
    if (!valid_original_node(original_node))
    {
        hir_semantic_parent[row] = INVALID;
        return;
    }

    uint parent_row = hir_semantic_parent_value[original_node];
    hir_semantic_parent[row] = valid_semantic_row(parent_row) ? parent_row : INVALID;
}
