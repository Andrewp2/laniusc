// Reduce per-function virtual-instruction row bounds to the maximum function
// span used by Pareas-style lockstep register allocation.

import atomics;
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

StructuredBuffer<uint> x86_func_slot_by_index;
StructuredBuffer<uint> x86_func_first_virtual_row;
StructuredBuffer<uint> x86_func_last_virtual_row;
StructuredBuffer<uint> x86_func_first_virtual_row_status;

RWStructuredBuffer<uint> x86_func_meta;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint FUNC_META_FUNC_COUNT = 0u;
static const uint FUNC_META_MAX_VIRTUAL_FUNC_ROWS = 5u;
static const uint X86_FUNC_FIRST_VIRTUAL_ROW_OK = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    return min(x86_func_first_virtual_row_status[3u], gParams.inst_capacity);
}

bool upstream_ok()
{
    return x86_func_first_virtual_row_status[0u] == X86_FUNC_FIRST_VIRTUAL_ROW_OK &&
           x86_func_first_virtual_row_status[1u] == 0u &&
           x86_func_first_virtual_row_status[3u] <= gParams.inst_capacity;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (!upstream_ok())
        return;

    uint func_i = linear_dispatch_id(tid);
    uint func_count = min(x86_func_meta[FUNC_META_FUNC_COUNT], gParams.function_slot_capacity);
    if (func_i >= func_count)
        return;

    uint slot = x86_func_slot_by_index[func_i];
    if (slot >= gParams.function_slot_capacity)
        return;

    uint first = x86_func_first_virtual_row[slot];
    uint last = x86_func_last_virtual_row[slot];
    uint inst_count = virtual_inst_count();
    if (first == INVALID || first > last || last >= inst_count)
        return;

    atomic_u32_max(x86_func_meta, FUNC_META_MAX_VIRTUAL_FUNC_ROWS, last - first + 1u);
}
