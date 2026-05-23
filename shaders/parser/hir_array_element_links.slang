// Seed array literal element links from grammar tree records.
//
// Array element lists are right-recursive: first elements seed the owning array
// literal, and later elements point at their previous element. A separate
// pointer-jump pass computes ordinals and owners.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirArray;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> hir_array_element_owner_a;
RWStructuredBuffer<uint> hir_array_element_link_a;
RWStructuredBuffer<uint> hir_array_element_rank_a;
RWStructuredBuffer<uint> hir_array_element_previous;
RWStructuredBuffer<uint> hir_array_element_owner_b;
RWStructuredBuffer<uint> hir_array_element_link_b;
RWStructuredBuffer<uint> hir_array_element_rank_b;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_MATCH_EXPR = 34u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirArray.uses_ll1 != 0u ? min(gHirArray.n, ll1_status[5u])
                                    : gHirArray.n;
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

bool is_array_element_container(uint prod)
{
    return prod == PROD_ARRAY_SOME || prod == PROD_ARRAY_AFTER_COMMA_MORE;
}

bool is_expr_node_kind(uint kind)
{
    return kind == HIR_EXPR ||
           kind == HIR_ASSIGN_EXPR ||
           kind == HIR_BINARY_EXPR ||
           kind == HIR_UNARY_EXPR ||
           kind == HIR_POSTFIX_EXPR ||
           kind == HIR_CALL_EXPR ||
           kind == HIR_INDEX_EXPR ||
           kind == HIR_MEMBER_EXPR ||
           kind == HIR_NAME_EXPR ||
           kind == HIR_LITERAL_EXPR ||
           kind == HIR_ARRAY_EXPR ||
           kind == HIR_STRUCT_LITERAL_EXPR ||
           kind == HIR_PATH_EXPR ||
           kind == HIR_MATCH_EXPR;
}

uint element_from_container(uint container)
{
    if (!valid_node(container) || !is_array_element_container(node_kind[container]))
        return INVALID;
    uint expr = first_child_node(container);
    return valid_node(expr) && is_expr_node_kind(hir_kind[expr]) ? expr : INVALID;
}

uint previous_element_for_after_comma(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_ARRAY_AFTER_COMMA_MORE)
        return INVALID;
    uint more = parent_node(container);
    uint previous_container = parent_node(more);
    return element_from_container(previous_container);
}

uint owner_seed_for_array_element_container(uint container)
{
    if (!valid_node(container) || node_kind[container] != PROD_ARRAY_SOME)
        return INVALID;
    uint owner = parent_node(container);
    return valid_node(owner) && hir_kind[owner] == HIR_ARRAY_EXPR ? owner : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirArray.n)
        return;

    hir_array_element_owner_a[node] = INVALID;
    hir_array_element_link_a[node] = INVALID;
    hir_array_element_rank_a[node] = 0u;
    hir_array_element_previous[node] = INVALID;
    hir_array_element_owner_b[node] = INVALID;
    hir_array_element_link_b[node] = INVALID;
    hir_array_element_rank_b[node] = 0u;

    if (!valid_node(node) || !is_expr_node_kind(hir_kind[node]))
        return;

    uint container = parent_node(node);
    uint prod = valid_node(container) ? node_kind[container] : INVALID;
    if (prod == PROD_ARRAY_SOME)
    {
        hir_array_element_owner_a[node] =
            owner_seed_for_array_element_container(container);
        return;
    }

    if (prod == PROD_ARRAY_AFTER_COMMA_MORE)
    {
        uint previous = previous_element_for_after_comma(container);
        if (valid_node(previous))
        {
            hir_array_element_link_a[node] = previous;
            hir_array_element_rank_a[node] = 1u;
            hir_array_element_previous[node] = previous;
        }
    }
}
