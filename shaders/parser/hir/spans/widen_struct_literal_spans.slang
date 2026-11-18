// Widen parser-owned struct literal spans after literal head links are known.
//
// The grammar owner for a struct literal starts at the field block. HIR users
// need the full source expression span, including the head path/name.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirStruct;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> prev_sibling;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> hir_token_pos;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_STRUCT_LITERAL_EXPR = 28u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirStruct.uses_status_count != 0u ? min(gHirStruct.n, tree_count_status[5u]) : gHirStruct.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint previous_sibling_node(uint node)
{
    uint previous = prev_sibling[node];
    return valid_node(previous) && parent[previous] == parent[node] ? previous : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || hir_kind[node] != HIR_STRUCT_LITERAL_EXPR)
        return;

    if (node_kind[node] != PROD_STRUCT_LIT)
        return;
    uint head = previous_sibling_node(node);
    if (!valid_node(head) || node_kind[head] != PROD_PATH)
        return;

    uint head_start = hir_token_pos[head];
    uint literal_start = hir_token_pos[node];
    if (head_start != INVALID &&
        (literal_start == INVALID || head_start < literal_start))
        hir_token_pos[node] = head_start;
}
