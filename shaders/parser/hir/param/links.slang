// Seed parser-owned function-parameter owners from the semantic HIR tree.
//
// Parameters are direct semantic children of their function. The semantic
// parent relation is therefore the canonical ownership source; reconstructing
// it through the grammar's right-recursive parameter-list shape would duplicate
// parsing work and require logarithmic pointer-jump rounds. Ordinals are
// assigned separately from the compact source-ordered parameter worklist.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirParam;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_node_dense_id;
StructuredBuffer<uint> hir_semantic_parent;
StructuredBuffer<uint> hir_semantic_dense_node;

RWStructuredBuffer<uint> hir_param_owner_a;
RWStructuredBuffer<uint> hir_param_link_a;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_FN = 3u;
static const uint HIR_PARAM = 4u;

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

uint semantic_owner_function(uint node)
{
    uint row = hir_node_dense_id[node];
    if (!valid_node(row))
        return INVALID;
    uint parent_row = hir_semantic_parent[row];
    if (!valid_node(parent_row))
        return INVALID;
    uint owner = hir_semantic_dense_node[parent_row];
    return valid_node(owner) && hir_kind[owner] == HIR_FN ? owner : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirParam.n)
        return;

    hir_param_owner_a[node] = INVALID;
    hir_param_link_a[node] = INVALID;

    if (!valid_node(node) || hir_kind[node] != HIR_PARAM)
        return;
    hir_param_owner_a[node] = semantic_owner_function(node);
}
