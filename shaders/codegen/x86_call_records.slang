import utils;

// Direct x86_64 call-record projection.
//
// This pass projects parser-owned call nodes, resolver-owned call targets, and
// type-check return metadata into backend call records. It deliberately does
// not lower calls yet; later x86 ABI and instruction planning passes consume
// these rows instead of rediscovering call syntax.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_start;
StructuredBuffer<uint> hir_call_arg_end;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;

RWStructuredBuffer<uint4> x86_call_record;
RWStructuredBuffer<uint4> x86_call_type_record;
RWStructuredBuffer<uint> call_record_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint X86_CALL_RECORDS_OK = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node_i)
{
    return node_i != INVALID && node_i < active_hir_node_count();
}

bool valid_token(uint token_i)
{
    return token_i != INVALID && token_i < gParams.n_tokens;
}

uint expr_record_slot(uint node, uint slot)
{
    return hir_expr_record[node * EXPR_RECORD_STRIDE + slot];
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_node(node))
            return INVALID;
        if (expr_form(node) != HIR_EXPR_FORWARD)
            return node;
        node = expr_left(node);
    }
    return INVALID;
}

uint callee_token_for_call(uint call_node)
{
    uint callee_node = resolve_expr(hir_call_callee_node[call_node]);
    return valid_node(callee_node) ? expr_value_token(callee_node) : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i == 0u)
    {
        call_record_status[0u] = X86_CALL_RECORDS_OK;
        call_record_status[1u] = 0u;
        call_record_status[2u] = INVALID;
    }

    if (node_i >= active_hir_node_count() || hir_kind[node_i] != HIR_CALL_EXPR)
        return;

    uint owner_fn = x86_node_func[node_i];
    uint callee_token = callee_token_for_call(node_i);
    uint target_fn = valid_token(callee_token) ? call_fn_index[callee_token] : INVALID;
    uint return_ty = valid_token(callee_token) ? call_return_type[callee_token] : 0u;
    uint return_ty_token = valid_token(callee_token) ? call_return_type_token[callee_token] : INVALID;

    x86_call_record[node_i] = uint4(
        owner_fn,
        target_fn,
        hir_call_arg_start[node_i],
        hir_call_arg_count[node_i]);
    x86_call_type_record[node_i] = uint4(
        return_ty,
        return_ty_token,
        callee_token,
        hir_call_arg_end[node_i]);

    uint old_count = 0u;
    InterlockedAdd(call_record_status[3u], 1u, old_count);
}
