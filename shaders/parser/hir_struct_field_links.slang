// Seed struct declaration/literal field links from grammar tree records.
//
// Struct field lists have the same right-recursive shape as call arguments:
// first fields seed the owning struct/literal, and later fields point at their
// previous field. A separate pointer-jump pass computes ordinals and owners.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirStruct;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> prev_sibling;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> hir_struct_field_type_node;
RWStructuredBuffer<uint> hir_struct_lit_head_node;
RWStructuredBuffer<uint> hir_struct_lit_field_value_node;
RWStructuredBuffer<uint> hir_struct_field_owner_a;
RWStructuredBuffer<uint> hir_struct_field_link_a;
RWStructuredBuffer<uint> hir_struct_field_rank_a;
RWStructuredBuffer<uint> hir_struct_lit_field_owner_a;
RWStructuredBuffer<uint> hir_struct_lit_field_link_a;
RWStructuredBuffer<uint> hir_struct_lit_field_rank_a;
RWStructuredBuffer<uint> hir_struct_lit_field_previous;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;
static const uint HIR_EXPR = 14u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirStruct.uses_ll1 != 0u ? min(gHirStruct.n, ll1_status[5u])
                                     : gHirStruct.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint parent_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint p = parent[node];
    return valid_node(p) ? p : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) ? child : INVALID;
}

uint previous_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint previous = prev_sibling[node];
    return valid_node(previous) && parent[previous] == parent[node] ?
        previous :
        INVALID;
}

uint first_child_with_hir_kind(uint node, uint kind)
{
    uint child = first_child_node(node);
    return valid_node(child) && parent[child] == node && hir_kind[child] == kind
        ? child
        : INVALID;
}

uint field_from_struct_container(uint container)
{
    if (!valid_node(container))
        return INVALID;
    uint prod = node_kind[container];
    if (prod != PROD_STRUCT_FIELDS_SOME &&
        prod != PROD_STRUCT_FIELDS_AFTER_COMMA_MORE)
        return INVALID;
    uint field = first_child_node(container);
    return valid_node(field) && node_kind[field] == PROD_STRUCT_FIELD
        ? field
        : INVALID;
}

uint literal_field_from_container(uint container)
{
    if (!valid_node(container))
        return INVALID;
    uint prod = node_kind[container];
    if (prod != PROD_STRUCT_LIT_FIELDS_SOME &&
        prod != PROD_STRUCT_LIT_FIELDS_AFTER_COMMA_MORE)
        return INVALID;
    uint field = first_child_node(container);
    return valid_node(field) && node_kind[field] == PROD_STRUCT_LIT_FIELD
        ? field
        : INVALID;
}

uint previous_struct_field_for_after_comma(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_STRUCT_FIELDS_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return field_from_struct_container(previous_container);
}

uint previous_literal_field_for_after_comma(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_STRUCT_LIT_FIELDS_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return literal_field_from_container(previous_container);
}

uint owner_seed_for_struct_field_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_STRUCT_FIELDS_SOME)
        return INVALID;
    uint owner = parent_node(container);
    return valid_node(owner) && node_kind[owner] == PROD_STRUCT ? owner : INVALID;
}

uint owner_seed_for_literal_field_container(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_STRUCT_LIT_FIELDS_SOME)
        return INVALID;
    uint owner = parent_node(container);
    return valid_node(owner) && node_kind[owner] == PROD_STRUCT_LIT ? owner : INVALID;
}

void seed_struct_field(uint node)
{
    uint container = parent_node(node);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;

    if (prod == PROD_STRUCT_FIELDS_SOME)
    {
        hir_struct_field_owner_a[node] =
            owner_seed_for_struct_field_container(container);
        return;
    }

    if (prod == PROD_STRUCT_FIELDS_AFTER_COMMA_MORE)
    {
        uint previous = previous_struct_field_for_after_comma(container);
        if (valid_node(previous))
        {
            hir_struct_field_link_a[node] = previous;
            hir_struct_field_rank_a[node] = 1u;
        }
    }
}

void seed_literal_field(uint node)
{
    uint container = parent_node(node);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;

    if (prod == PROD_STRUCT_LIT_FIELDS_SOME)
    {
        hir_struct_lit_field_owner_a[node] =
            owner_seed_for_literal_field_container(container);
        return;
    }

    if (prod == PROD_STRUCT_LIT_FIELDS_AFTER_COMMA_MORE)
    {
        uint previous = previous_literal_field_for_after_comma(container);
        if (valid_node(previous))
        {
            hir_struct_lit_field_link_a[node] = previous;
            hir_struct_lit_field_rank_a[node] = 1u;
            hir_struct_lit_field_previous[node] = previous;
        }
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirStruct.n)
        return;

    hir_struct_field_owner_a[node] = INVALID;
    hir_struct_field_link_a[node] = INVALID;
    hir_struct_field_rank_a[node] = 0u;
    hir_struct_lit_field_owner_a[node] = INVALID;
    hir_struct_lit_field_link_a[node] = INVALID;
    hir_struct_lit_field_rank_a[node] = 0u;
    hir_struct_lit_field_previous[node] = INVALID;

    if (!valid_node(node))
        return;

    uint prod = node_kind[node];
    if (prod == PROD_STRUCT_FIELD)
    {
        hir_struct_field_type_node[node] =
            first_child_with_hir_kind(node, HIR_TYPE);
        seed_struct_field(node);
        return;
    }

    if (prod == PROD_STRUCT_LIT)
    {
        uint previous = previous_sibling_node(node);
        if (valid_node(previous) && node_kind[previous] == PROD_PATH)
            hir_struct_lit_head_node[node] = previous;
        return;
    }

    if (prod == PROD_STRUCT_LIT_FIELD)
    {
        hir_struct_lit_field_value_node[node] =
            first_child_with_hir_kind(node, HIR_EXPR);
        seed_literal_field(node);
    }
}
