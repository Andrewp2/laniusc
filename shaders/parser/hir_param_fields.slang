// Publish parser-owned function parameter metadata from pointer-jumped links.
//
// Parameter consumers should use these rows instead of deriving parameter
// identity or ordinal from token neighborhoods. Owner and ordinal are produced
// by the preceding linked-list passes, not by walking ancestors here.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirParam;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_param_owner_a;
StructuredBuffer<uint> hir_param_rank_a;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;

RWStructuredBuffer<uint4> hir_param_record;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_PARAM = 4u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirParam.uses_ll1 != 0u ? min(gHirParam.n, ll1_status[5u]) : gHirParam.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

uint semantic_row_node(uint row)
{
    if (row >= active_semantic_count())
        return INVALID;
    uint node = hir_semantic_dense_node[row];
    return valid_node(node) ? node : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint node = semantic_row_node(row);
    if (node == INVALID)
        return;

    hir_param_record[node] = uint4(INVALID, INVALID, INVALID, INVALID);
    if (hir_kind[node] != HIR_PARAM)
        return;

    uint fn_node = hir_param_owner_a[node];
    if (!valid_node(fn_node))
        return;

    uint name_token = hir_token_pos[node];
    if (name_token == INVALID)
        return;

    hir_param_record[node] = uint4(
        fn_node,
        hir_param_rank_a[node],
        name_token,
        node);
}
