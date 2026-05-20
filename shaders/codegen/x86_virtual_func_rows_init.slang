// Initialize per-function virtual instruction row bounds.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_node_decl_token;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> x86_func_first_virtual_row;
RWStructuredBuffer<uint> x86_func_last_virtual_row;
RWStructuredBuffer<uint> x86_func_param_reg_mask;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint function_slot_key(uint node)
{
    uint slot = hir_node_decl_token[node];
    if (slot < gParams.n_tokens)
        return slot;
    slot = hir_token_pos[node];
    return slot < gParams.n_tokens ? slot : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (node >= gParams.n_hir_nodes || hir_kind[node] != HIR_FN)
        return;

    uint slot = function_slot_key(node);
    if (slot == INVALID)
        return;

    x86_func_first_virtual_row[slot] = INVALID;
    x86_func_last_virtual_row[slot] = 0u;
    x86_func_param_reg_mask[slot] = 0u;
}
