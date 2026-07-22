// Scatter parser-produced compact HIR call-argument rows directly.
//
// Per-call argument counts have already been prefix-scanned, so each argument
// row writes to row_start[call] + ordinal. That makes `(call_node, ordinal)`
// lookup stable even when nested call HIR rows interleave in source order.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirCallArg { uint call; uint value; uint ordinal; uint file_id; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;

RWStructuredBuffer<uint> call_arg_row_node;
RWStructuredBuffer<uint> call_arg_row_call_node;
RWStructuredBuffer<uint> call_arg_row_ordinal;
RWStructuredBuffer<uint> call_arg_row_start;
RWStructuredBuffer<uint> call_arg_row_count;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node, uint n)
{
    return node != INVALID && node < n;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint n = active_hir_node_count();
    uint row_count = min(compact_call_arg_count[0u], gParams.n_hir_nodes);
    if (row >= row_count)
        return;

    HirCallArg arg = compact_call_args[row];
    uint call_node = arg.call;
    uint node = arg.value;
    uint ordinal = arg.ordinal;
    if (!valid_node(call_node, n) || !valid_node(node, n) ||
        compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return;

    HirPayload call = compact_hir_payload[call_node];
    uint start = call.b;
    uint count = call.c;
    if (count == 0u || ordinal >= count)
        return;
    if (row != start + ordinal || row < start || row >= row_count)
        return;

    call_arg_row_node[row] = node;
    call_arg_row_call_node[row] = call_node;
    call_arg_row_ordinal[row] = ordinal;
    call_arg_row_start[call_node] = start;
    call_arg_row_count[call_node] = count;
}
