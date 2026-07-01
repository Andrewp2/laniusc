// Count reachable WASM function declarations after call-graph propagation.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> body_plan;
RWStructuredBuffer<uint> wasm_func_decl_flag;
RWStructuredBuffer<uint> wasm_func_flag;

static const uint BODY_PLAN_FUNCTION_COUNT = 31u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token_i = linear_dispatch_id(tid);
    if (token_i >= gParams.n_tokens)
        return;

    if (wasm_func_flag[token_i] == 0u)
        return;

    if (wasm_func_decl_flag[token_i] == 0u)
    {
        wasm_func_flag[token_i] = 0u;
        return;
    }

    atomic_u32_add(body_plan, BODY_PLAN_FUNCTION_COUNT, 1u);
}
