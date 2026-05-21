// Mark HIR function records for deterministic function-slot compaction.
//
// Function discovery materializes per-node records. This pass turns the HIR_FN
// record set into a compact-scan input so the slot index list is built by
// prefix rank rather than by an atomic append order.

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

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;

RWStructuredBuffer<uint> x86_func_slot_flags;

static const uint HIR_FN = 3u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    uint active = active_hir_node_count();
    if (row > active)
        return;

    x86_func_slot_flags[row] = row < active && hir_kind[row] == HIR_FN ? 1u : 0u;
}
