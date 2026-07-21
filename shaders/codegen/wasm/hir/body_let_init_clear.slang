// Clear token-indexed let-initializer records before parallel publication.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> body_let_init_expr_by_decl_token;
RWStructuredBuffer<uint> body_let_init_hir_by_decl_token;

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

    body_let_init_expr_by_decl_token[token_i] = INVALID;
    body_let_init_hir_by_decl_token[token_i] = INVALID;
}
