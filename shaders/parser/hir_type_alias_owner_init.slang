// Seed nearest item-owner propagation over dense semantic-HIR rows.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirTypeAliasOwner;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_parent;
StructuredBuffer<uint> hir_item_kind;

RWStructuredBuffer<uint> hir_type_alias_owner_link_a;
RWStructuredBuffer<uint> hir_type_alias_owner_value_a;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_KIND_NONE = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirTypeAliasOwner.uses_ll1 != 0u ? min(gHirTypeAliasOwner.n, ll1_status[5u])
                                             : gHirTypeAliasOwner.n;
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
    if (!valid_semantic_row(row))
        return;

    uint node = hir_semantic_dense_node[row];
    uint parent = hir_semantic_parent[row];
    hir_type_alias_owner_link_a[row] = valid_semantic_row(parent) ? parent : INVALID;
    hir_type_alias_owner_value_a[row] =
        valid_original_node(node) && hir_item_kind[node] != HIR_ITEM_KIND_NONE ? node : INVALID;
}
