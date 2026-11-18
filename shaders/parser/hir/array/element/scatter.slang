// Publish pointer-jumped array element owners, ordinals, counts, and links.
//
// The pass runs over the array element list (hir_list_rank_node) that the
// element links pass marked; other rows are not read or written.

import atomics;

struct Params
{
    uint n;
    uint uses_status_count;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirArray;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_array_element_owner_a;
StructuredBuffer<uint> hir_array_element_rank_a;
StructuredBuffer<uint> hir_array_element_previous;
StructuredBuffer<uint> hir_list_rank_node;
StructuredBuffer<uint> hir_list_rank_count;

RWStructuredBuffer<uint> hir_array_lit_first_element;
RWStructuredBuffer<uint> hir_array_lit_element_count;
RWStructuredBuffer<uint> hir_array_element_parent_lit;
RWStructuredBuffer<uint> hir_array_element_ordinal;
RWStructuredBuffer<uint> hir_array_element_next;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ARRAY_EXPR = 24u;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= hir_list_rank_count[0u])
        return;
    uint node = hir_list_rank_node[row];
    if (!valid_node(node))
        return;

    uint owner = hir_array_element_owner_a[node];
    if (!valid_node(owner) || hir_kind[owner] != HIR_ARRAY_EXPR)
        return;

    uint ordinal = hir_array_element_rank_a[node];
    uint previous = hir_array_element_previous[node];
    hir_array_element_parent_lit[node] = owner;
    hir_array_element_ordinal[node] = ordinal;
    if (gHirArray.retain_debug_rows != 0u)
    {
        atomic_u32_min(hir_array_lit_first_element, owner, node);
        atomic_u32_max(hir_array_lit_element_count, owner, ordinal + 1u);
        if (valid_node(previous))
            hir_array_element_next[previous] = node;
    }
}
