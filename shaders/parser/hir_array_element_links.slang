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

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR = 14u;
static const uint HIR_ARRAY_EXPR = 24u;

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

uint element_from_container(uint container)
{
    if (!valid_node(container) || !is_array_element_container(node_kind[container]))
        return INVALID;
    uint expr = first_child_node(container);
    return valid_node(expr) && hir_kind[expr] == HIR_EXPR ? expr : INVALID;
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

    if (!valid_node(node) || hir_kind[node] != HIR_EXPR)
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
