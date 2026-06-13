// Widen parser-owned struct literal spans after literal head links are known.
//
// The grammar owner for a struct literal starts at the field block. HIR users
// need the full source expression span, including the head path/name.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirStruct;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_struct_lit_head_node;

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
    return gHirStruct.uses_ll1 != 0u ? min(gHirStruct.n, ll1_status[5u]) : gHirStruct.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || hir_kind[node] != HIR_STRUCT_LITERAL_EXPR)
        return;

    uint head = hir_struct_lit_head_node[node];
    if (!valid_node(head))
        return;

    uint head_start = hir_token_pos[head];
    uint literal_start = hir_token_pos[node];
    if (head_start != INVALID &&
        (literal_start == INVALID || head_start < literal_start))
        hir_token_pos[node] = head_start;
}
