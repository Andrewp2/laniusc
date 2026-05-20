// Publish pointer-jumped path leaf nodes onto HIR path/type records.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_value_node;
StructuredBuffer<uint> hir_type_path_leaf_value_a;

RWStructuredBuffer<uint> hir_type_path_leaf_node;
RWStructuredBuffer<uint> hir_type_path_owner_by_leaf;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_TYPE_FORM_PATH = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirType.uses_ll1 != 0u ? min(gHirType.n, ll1_status[5u]) : gHirType.n;
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
    if (node >= gHirType.n || !valid_node(node))
        return;

    if (hir_kind[node] == HIR_PATH_EXPR)
    {
        uint leaf = hir_type_path_leaf_value_a[node];
        hir_type_path_leaf_node[node] = leaf;
        return;
    }

    if (hir_type_form[node] != HIR_TYPE_FORM_PATH)
        return;

    uint path_node = hir_type_value_node[node];
    if (!valid_node(path_node))
        return;

    uint leaf = hir_type_path_leaf_value_a[path_node];
    hir_type_path_leaf_node[node] = leaf;
    if (valid_node(leaf))
        hir_type_path_owner_by_leaf[leaf] = node;
}
