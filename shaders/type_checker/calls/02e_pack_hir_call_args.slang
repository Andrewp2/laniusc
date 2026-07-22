// Publish token-keyed call summaries from the compact semantic HIR.
//
// One dense call row handles zero-argument calls. The first row of each
// compact `HirCallArg` segment publishes the non-empty summary, so nested or
// wide argument lists require no raw-tree reconstruction and no contended
// per-argument writes.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirCallArg { uint call; uint value; uint ordinal; uint file_id; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;
RWStructuredBuffer<uint4> call_arg_record;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint active_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint active_arg_count()
{
    return min(gParams.n_hir_nodes, compact_call_arg_count[0u]);
}

bool valid_hir(uint node)
{
    return node != INVALID && node < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint callee_token(uint call)
{
    if (!valid_hir(call) || compact_hir_core[call].kind != HIR_CALL_EXPR)
        return INVALID;
    uint callee = compact_hir_payload[call].a;
    if (!valid_hir(callee))
        return INVALID;
    HirCore core = compact_hir_core[callee];
    HirPayload payload = compact_hir_payload[callee];
    uint token = core.kind == HIR_MEMBER_EXPR ? payload.c : payload.d;
    if (!valid_token(token))
        token = core.token_start;
    return valid_token(token) ? token : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = active_hir_count();
    if (row < hir_count && compact_hir_core[row].kind == HIR_CALL_EXPR)
    {
        HirPayload call = compact_hir_payload[row];
        uint token = callee_token(row);
        if (call.c == 0u && valid_token(token))
            call_arg_record[token] = uint4(INVALID, INVALID, row, 0u);
    }

    if (row >= active_arg_count())
        return;
    HirCallArg arg = compact_call_args[row];
    if (arg.ordinal != 0u || !valid_hir(arg.call) || !valid_hir(arg.value))
        return;
    HirPayload call = compact_hir_payload[arg.call];
    if (call.b != row || call.c == 0u)
        return;
    uint token = callee_token(arg.call);
    if (!valid_token(token))
        return;
    HirCore value = compact_hir_core[arg.value];
    uint start = valid_token(value.token_start) ? value.token_start : INVALID;
    uint end = value.token_end != INVALID && value.token_end <= gParams.n_tokens
        ? value.token_end
        : INVALID;
    call_arg_record[token] = start != INVALID && end != INVALID && start < end
        ? uint4(start, end, arg.call, call.c)
        : uint4(INVALID, INVALID, arg.call, call.c);
}
