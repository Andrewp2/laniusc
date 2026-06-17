// Assign parser-visible function-parameter ordinals as segment offsets.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirParam;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_param_owner_a;
StructuredBuffer<uint> hir_param_rank_b;
StructuredBuffer<uint> hir_list_rank_node;
StructuredBuffer<uint> hir_list_rank_count;

RWStructuredBuffer<uint> hir_param_rank_a;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirParam.uses_status_count != 0u ? min(gHirParam.n, tree_count_status[5u]) : gHirParam.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= gHirParam.n || row >= hir_list_rank_count[0u])
        return;

    uint node = hir_list_rank_node[row];
    if (!valid_node(node))
        return;

    uint owner = hir_param_owner_a[node];
    if (!valid_node(owner))
        return;

    uint base = hir_param_rank_b[owner];
    hir_param_rank_a[node] = base != INVALID && row >= base ? row - base : INVALID;
}
