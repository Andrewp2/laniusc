// Publish pointer-jumped array element owners, ordinals, counts, and links.

import atomics;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirArray;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_array_element_owner_a;
StructuredBuffer<uint> hir_array_element_rank_a;
StructuredBuffer<uint> hir_array_element_previous;

RWStructuredBuffer<uint> hir_array_lit_first_element;
RWStructuredBuffer<uint> hir_array_lit_element_count;
RWStructuredBuffer<uint> hir_array_element_parent_lit;
RWStructuredBuffer<uint> hir_array_element_ordinal;
RWStructuredBuffer<uint> hir_array_element_next;

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
    return gHirArray.uses_status_count != 0u ? min(gHirArray.n, tree_count_status[5u])
                                    : gHirArray.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirArray.n || !valid_node(node) || !is_expr_node_kind(hir_kind[node]))
        return;

    uint owner = hir_array_element_owner_a[node];
    if (!valid_node(owner))
        return;

    uint ordinal = hir_array_element_rank_a[node];
    uint previous = hir_array_element_previous[node];
    hir_array_element_parent_lit[node] = owner;
    hir_array_element_ordinal[node] = ordinal;
    atomic_u32_min(hir_array_lit_first_element, owner, node);
    atomic_u32_max(hir_array_lit_element_count, owner, ordinal + 1u);
    if (valid_node(previous))
        hir_array_element_next[previous] = node;
}
