// Widen parser-owned call expression spans after callee links are known.
//
// Postfix call grammar rows naturally start at the argument list. HIR call
// records represent the whole call expression, including the callee.

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirCall;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_call_callee_node;

RWStructuredBuffer<uint> hir_token_pos;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_CALL_EXPR = 19u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirCall.uses_ll1 != 0u ? min(gHirCall.n, ll1_status[5u]) : gHirCall.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

uint semantic_row_node(uint row)
{
    if (row >= active_semantic_count())
        return INVALID;
    uint node = hir_semantic_dense_node[row];
    return valid_node(node) ? node : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint node = semantic_row_node(row);
    if (node == INVALID || hir_kind[node] != HIR_CALL_EXPR)
        return;

    uint callee = hir_call_callee_node[node];
    if (!valid_node(callee))
        return;

    uint callee_start = hir_token_pos[callee];
    uint call_start = hir_token_pos[node];
    if (callee_start != INVALID &&
        (call_start == INVALID || callee_start < call_start))
        hir_token_pos[node] = callee_start;
}
