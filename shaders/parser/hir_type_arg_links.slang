// Seed generic type-argument links from grammar tree records.
//
// Type argument lists are right-recursive. First arguments seed the owning type
// expression, and later arguments point at their previous argument. A separate
// pointer-jump pass computes owners and ordinals.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> prev_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_type_path_owner_by_leaf;

RWStructuredBuffer<uint> hir_type_arg_owner_a;
RWStructuredBuffer<uint> hir_type_arg_link_a;
RWStructuredBuffer<uint> hir_type_arg_rank_a;
RWStructuredBuffer<uint> hir_type_arg_previous;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;
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

uint next_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = next_sibling[node];
    return valid_node(sibling) && parent[sibling] == parent[node] ? sibling : INVALID;
}

uint previous_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint previous = prev_sibling[node];
    return valid_node(previous) && parent[previous] == parent[node] ? previous : INVALID;
}

bool is_type_arg_container(uint prod)
{
    return prod == PROD_TYPE_ARGS_SOME ||
           prod == PROD_TYPE_ARGS_AFTER_COMMA_MORE;
}

bool is_type_path_container(uint prod)
{
    return prod == PROD_TYPE_PATH || prod == PROD_TYPE_PATH_MORE ||
           prod == PROD_PATH_MORE;
}

bool is_type_path_segment(uint prod)
{
    return prod == PROD_TYPE_PATH_IDENT || prod == PROD_PATH_IDENT;
}

uint arg_from_container(uint container)
{
    if (!valid_node(container) || !is_type_arg_container(node_kind[container]))
        return INVALID;
    uint arg = first_child_node(container);
    return valid_node(arg) && hir_kind[arg] == HIR_TYPE ? arg : INVALID;
}

uint previous_arg_for_after_comma(uint container)
{
    if (!valid_node(container) ||
        node_kind[container] != PROD_TYPE_ARGS_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    uint previous = arg_from_container(previous_container);
    if (valid_node(previous))
        return previous;
    return valid_node(previous_container) && hir_kind[previous_container] == HIR_TYPE
        ? first_arg_for_type_owner(previous_container)
        : INVALID;
}

uint owner_seed_for_arg_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_TYPE_ARGS_SOME)
        return INVALID;
    uint owner = parent_node(container);
    return valid_node(owner) && hir_kind[owner] == HIR_TYPE ? owner : INVALID;
}

bool valid_path_type_owner(uint owner, uint leaf)
{
    return owner != 0u &&
           valid_node(owner) &&
           hir_kind[owner] == HIR_TYPE &&
           hir_type_form[owner] == HIR_TYPE_FORM_PATH &&
           hir_type_path_leaf_node[owner] == leaf;
}

uint owner_seed_for_path_arg(uint node)
{
    uint leaf = previous_sibling_node(node);
    if (!valid_node(leaf) || !is_type_path_segment(node_kind[leaf]))
        return INVALID;

    uint owner = hir_type_path_owner_by_leaf[leaf];
    return valid_path_type_owner(owner, leaf) ? owner : INVALID;
}

uint first_arg_for_type_owner(uint owner)
{
    if (!valid_node(owner) || hir_type_form[owner] != HIR_TYPE_FORM_PATH)
        return INVALID;

    uint leaf = hir_type_path_leaf_node[owner];
    uint first = next_sibling_node(leaf);
    return valid_node(first) && hir_kind[first] == HIR_TYPE ? first : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirType.n)
        return;

    hir_type_arg_owner_a[node] = INVALID;
    hir_type_arg_link_a[node] = INVALID;
    hir_type_arg_rank_a[node] = 0u;
    hir_type_arg_previous[node] = INVALID;

    if (!valid_node(node) || hir_kind[node] != HIR_TYPE)
        return;

    uint container = parent_node(node);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;
    uint path_owner = owner_seed_for_path_arg(node);
    if (valid_node(path_owner))
    {
        hir_type_arg_owner_a[node] = path_owner;
        return;
    }

    if (prod == PROD_TYPE_ARGS_SOME)
    {
        hir_type_arg_owner_a[node] = owner_seed_for_arg_container(container);
        return;
    }

    if (prod == PROD_TYPE_ARGS_AFTER_COMMA_MORE)
    {
        uint previous = previous_arg_for_after_comma(container);
        if (valid_node(previous))
        {
            hir_type_arg_link_a[node] = previous;
            hir_type_arg_rank_a[node] = 1u;
            hir_type_arg_previous[node] = previous;
        }
    }
}
