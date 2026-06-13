// Pointer-jump type-path leaf links.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_type_path_leaf_link_in;
StructuredBuffer<uint> hir_type_path_leaf_value_in;

RWStructuredBuffer<uint> hir_type_path_leaf_link_out;
RWStructuredBuffer<uint> hir_type_path_leaf_value_out;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirType.uses_status_count != 0u ? min(gHirType.n, tree_count_status[5u]) : gHirType.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirType.n)
        return;

    if (!valid_node(node))
    {
        hir_type_path_leaf_link_out[node] = INVALID;
        hir_type_path_leaf_value_out[node] = INVALID;
        return;
    }

    uint link = hir_type_path_leaf_link_in[node];
    uint value = hir_type_path_leaf_value_in[node];
    if (!valid_node(link) || link == node)
    {
        hir_type_path_leaf_link_out[node] = INVALID;
        hir_type_path_leaf_value_out[node] = value;
        return;
    }

    uint linked_value = hir_type_path_leaf_value_in[link];
    uint linked_link = hir_type_path_leaf_link_in[link];
    hir_type_path_leaf_value_out[node] =
        valid_node(linked_value) ? linked_value : value;
    hir_type_path_leaf_link_out[node] =
        valid_node(linked_link) ? linked_link : INVALID;
}
