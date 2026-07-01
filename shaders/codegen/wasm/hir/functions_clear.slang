// Clear token-keyed WASM function records.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> wasm_func_flag;
RWStructuredBuffer<uint> wasm_func_decl_flag;
RWStructuredBuffer<uint> wasm_func_slot_by_token;
RWStructuredBuffer<uint> wasm_func_token_by_slot;
RWStructuredBuffer<uint> wasm_func_param_ordinal_by_decl_token;
RWStructuredBuffer<uint> wasm_func_body_len_by_token;
RWStructuredBuffer<uint> wasm_func_local_max_by_token;
RWStructuredBuffer<uint> wasm_func_return_count_by_token;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_return_token_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;

static const uint INVALID = 0xffffffffu;
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

    wasm_func_flag[token_i] = 0u;
    wasm_func_decl_flag[token_i] = 0u;
    wasm_func_slot_by_token[token_i] = INVALID;
    wasm_func_token_by_slot[token_i] = INVALID;
    wasm_func_param_ordinal_by_decl_token[token_i] = INVALID;
    wasm_func_body_len_by_token[token_i] = 0u;
    wasm_func_local_max_by_token[token_i] = INVALID;
    wasm_func_return_count_by_token[token_i] = 0u;
    wasm_func_invalid_count_by_token[token_i] = 0u;
    wasm_func_return_token_by_token[token_i] = INVALID;
    wasm_func_detail_by_token[token_i] = INVALID;
}
