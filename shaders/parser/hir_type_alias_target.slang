// Publish each type-alias item's first contained type node from dense semantic-HIR rows.
//
// A prior pointer-jump pass computes the nearest item owner for every semantic
// row. This pass scatters type nodes only when that nearest owner is a
// type-alias item, producing the preorder-first target type node without source
// text, token spelling, token neighborhoods, or child/sibling walks.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirTypeAliasTarget;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_type_alias_owner_value;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_type_form;

RWStructuredBuffer<uint> hir_type_alias_target_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_NONE = 0u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirTypeAliasTarget.uses_ll1 != 0u ? min(gHirTypeAliasTarget.n, ll1_status[5u])
                                              : gHirTypeAliasTarget.n;
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
    if (!valid_original_node(node) || hir_kind[node] != HIR_TYPE ||
        hir_type_form[node] == HIR_TYPE_FORM_NONE)
        return;

    uint owner = hir_type_alias_owner_value[row];
    if (!valid_original_node(owner) || owner == node ||
        hir_item_kind[owner] != HIR_ITEM_KIND_TYPE_ALIAS)
        return;

    InterlockedMin(hir_type_alias_target_node[owner], node);
}
