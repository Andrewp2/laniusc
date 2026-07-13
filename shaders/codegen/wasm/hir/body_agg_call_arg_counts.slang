// Count ABI argument records needed by aggregate direct-call body fragments.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint4> body_fragment_aux;

RWStructuredBuffer<uint> wasm_agg_call_arg_count_by_fragment;

static const uint BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32 = 44u;
static const uint BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32 = 45u;
static const uint BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 = 46u;
static const uint BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 = 29u;
static const uint BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 = 23u;
static const uint BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 = 24u;
static const uint BODY_FRAGMENT_LET_DIRECT_CALL_I32 = 25u;
static const uint BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 = 26u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32 = 27u;
static const uint BODY_FRAGMENT_DIRECT_CALL_VOID = 52u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint fragment_i = linear_dispatch_id(tid);
    uint fragment_capacity = gParams.n_tokens * 2u;
    if (fragment_i >= fragment_capacity)
        return;

    uint kind = body_fragment_meta[fragment_i].x;
    uint count =
        kind == BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32 ||
        kind == BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32 ||
        kind == BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 ||
        kind == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 ||
        kind == BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 ||
        kind == BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 ||
        kind == BODY_FRAGMENT_LET_DIRECT_CALL_I32 ||
        kind == BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 ||
        kind == BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32 ||
        kind == BODY_FRAGMENT_DIRECT_CALL_VOID
            ? body_fragment_aux[fragment_i].y
            : 0u;
    wasm_agg_call_arg_count_by_fragment[fragment_i] = count;
}
