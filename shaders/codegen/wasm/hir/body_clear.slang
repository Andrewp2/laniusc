// Clear token-indexed WASM body fragment records before per-node emission.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_NONE = 0u;
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

    body_fragment_len[token_i] = 0u;
    body_fragment_meta[token_i] = uint4(BODY_FRAGMENT_NONE, 0u, 0u, INVALID);
}
