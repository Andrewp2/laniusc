// Initialize per-function virtual instruction row bounds.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
    uint virtual_next_call_step_count;
    uint regalloc_rows_per_chunk;
    uint regalloc_chunk_count;
    uint function_slot_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_func_meta;
StructuredBuffer<uint> x86_func_slot_by_index;

RWStructuredBuffer<uint> x86_func_first_virtual_row;
RWStructuredBuffer<uint> x86_func_last_virtual_row;
RWStructuredBuffer<uint> x86_func_param_reg_mask;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint FUNC_META_FUNC_COUNT = 0u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint func_i = linear_dispatch_id(tid);
    uint func_count = min(x86_func_meta[FUNC_META_FUNC_COUNT], gParams.function_slot_capacity);
    if (func_i >= func_count)
        return;

    uint slot = x86_func_slot_by_index[func_i];
    if (slot >= gParams.n_tokens)
        return;

    x86_func_first_virtual_row[slot] = INVALID;
    x86_func_last_virtual_row[slot] = 0u;
    x86_func_param_reg_mask[slot] = 0u;
}
