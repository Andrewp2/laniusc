// Seed type-path leaf links from grammar tree records.
//
// Type paths are right-recursive. Each path container records its current
// segment and links to the next path-more container when one exists. A separate
// pointer-jump pass propagates the final segment back to the path root.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;

RWStructuredBuffer<uint> hir_type_path_leaf_link_a;
RWStructuredBuffer<uint> hir_type_path_leaf_value_a;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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
    return valid_node(sibling) ? sibling : INVALID;
}

bool is_value_path_container(uint prod)
{
    return prod == PROD_PATH || prod == PROD_PATH_MORE;
}

bool is_type_path_container(uint prod)
{
    return prod == PROD_TYPE_PATH || prod == PROD_TYPE_PATH_MORE;
}

bool is_path_container(uint prod)
{
    return is_type_path_container(prod) || is_value_path_container(prod);
}

bool is_type_path_segment(uint prod)
{
    return prod == PROD_TYPE_PATH_IDENT || prod == PROD_PATH_IDENT;
}

bool is_type_path_tail(uint prod)
{
    return prod == PROD_TYPE_PATH_MORE || prod == PROD_PATH_MORE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirType.n)
        return;

    hir_type_path_leaf_link_a[node] = INVALID;
    hir_type_path_leaf_value_a[node] = INVALID;

    if (!valid_node(node) || !is_path_container(node_kind[node]))
        return;

    uint segment = first_child_node(node);
    if (!valid_node(segment) || !is_type_path_segment(node_kind[segment]))
        return;

    hir_type_path_leaf_value_a[node] = segment;

    uint tail = next_sibling_node(segment);
    if (valid_node(tail) && is_type_path_tail(node_kind[tail]))
        hir_type_path_leaf_link_a[node] = tail;
}
