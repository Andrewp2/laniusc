// Scatter function slots by prefix rank.
//
// This is the Pareas-style compaction counterpart to x86_func_slot_flags: the
// scan gives each HIR_FN node a stable ordinal, then this pass writes the dense
// function-slot table and publishes the total function count.

import atomics;
import gpu_index;
import prefix_scan;

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

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> x86_func_slot_flags;
StructuredBuffer<uint> x86_func_slot_scan_local_prefix;
StructuredBuffer<uint> x86_func_slot_scan_block_prefix;

RWStructuredBuffer<uint> x86_func_meta;
RWStructuredBuffer<uint> x86_func_slot_by_node;
RWStructuredBuffer<uint> x86_func_slot_by_index;

static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint FUNC_META_FUNC_COUNT = 0u;
static const uint FUNC_META_MAIN_SLOT = 2u;
static const uint FUNC_META_MAIN_NODE = 4u;
static const uint INVALID = 0xffffffffu;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

uint slot_prefix(uint row)
{
    return global_exclusive_prefix(
        row,
        WG_SIZE,
        x86_func_slot_scan_local_prefix,
        x86_func_slot_scan_block_prefix);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint active = active_hir_node_count();
    if (row > active)
        return;

    if (row == active)
    {
        uint total = slot_prefix(row);
        x86_func_meta[FUNC_META_FUNC_COUNT] = total;
        return;
    }

    if (x86_func_slot_flags[row] == 0u)
        return;

    uint ordinal = slot_prefix(row);
    if (ordinal < gParams.function_slot_capacity)
    {
        x86_func_slot_by_node[row] = ordinal;
        x86_func_slot_by_index[ordinal] = ordinal;
        if (row == x86_func_meta[FUNC_META_MAIN_NODE])
            atomic_u32_min(x86_func_meta, FUNC_META_MAIN_SLOT, ordinal);
    }
    else
    {
        x86_func_slot_by_node[row] = INVALID;
    }
}
