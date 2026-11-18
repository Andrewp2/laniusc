// Seed nearest semantic declaration-owner propagation over dense HIR rows.
// Type aliases consume this relation directly; generic side-table builders
// reuse it rather than walking the raw parse parent chain independently.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirTypeAliasOwner;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_parent;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> raw_to_hir;
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
    return gHirTypeAliasOwner.uses_status_count != 0u ? min(gHirTypeAliasOwner.n, tree_count_status[5u])
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

uint item_kind_for_raw(uint node)
{
    if (!valid_original_node(node))
        return HIR_ITEM_KIND_NONE;
    uint item_row = gHirTypeAliasOwner.retain_debug_rows != 0u ? node : raw_to_hir[node];
    return item_row != INVALID ? hir_item_kind[item_row] : HIR_ITEM_KIND_NONE;
}

uint declaration_owner(uint node)
{
    if (!valid_original_node(node))
        return INVALID;
    if (item_kind_for_raw(node) != HIR_ITEM_KIND_NONE)
        return node;
    uint production = node_kind[node];
    if (production == PROD_IMPL_INHERENT || production == PROD_IMPL_TRAIT ||
        production == PROD_IMPL_FN || production == PROD_TRAIT_METHOD ||
        production == PROD_TRAIT_METHOD_PUB)
        return node;
    if (production == PROD_ITEM_IMPL || production == PROD_PUB_IMPL)
    {
        uint child = first_child[node];
        if (valid_original_node(child) &&
            (node_kind[child] == PROD_IMPL_INHERENT || node_kind[child] == PROD_IMPL_TRAIT))
            return child;
    }
    return INVALID;
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
    hir_type_alias_owner_value_a[row] = declaration_owner(node);
}
