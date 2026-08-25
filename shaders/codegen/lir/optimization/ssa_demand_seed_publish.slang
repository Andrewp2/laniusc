// Publishes the canonical seed prefix into the exact sparse set and initializes
// the first global work frontier. The queue is consumed by the following
// persistent closure dispatch.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_sparse_work;
import gpu_index;

struct Params
{
    uint block_capacity;
    uint edge_capacity;
    uint access_capacity;
    uint declaration_capacity;
    uint declaration_block_capacity;
    uint demand_capacity;
    uint worker_count;
    uint max_radix_blocks;
    uint incoming_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_ssa_demand_seed_total;
StructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;
RWStructuredBuffer<uint> opt_ir_ssa_sparse_declaration;
RWStructuredBuffer<uint> opt_ir_ssa_sparse_block;
RWStructuredBuffer<uint> opt_ir_ssa_work_queue;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_capacity(uint required, uint available)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = available;
}

void report_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(
        lowering_status[0u].diagnostic_reason, 0u, 101u, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint seed_total = min(
        opt_ir_ssa_demand_seed_total[0u], gParams.demand_capacity);
    if (row >= seed_total) return;

    OptIrSsaDemand demand = opt_ir_ssa_demands[row];
    uint hash_capacity = gParams.demand_capacity * 2u + 1u;
    uint hash_slot = 0xffffffffu;
    uint result = ssa_sparse_insert_key(
        demand.declaration,
        demand.block,
        hash_capacity,
        opt_ir_ssa_sparse_declaration,
        opt_ir_ssa_sparse_block,
        hash_slot);
    if (result == SSA_SPARSE_INSERT_FULL)
        report_capacity(hash_capacity + 1u, hash_capacity);
    else if (result != SSA_SPARSE_INSERTED)
        report_structure_failure(row);

    // Seed rows are already dense and unique, so no atomic reservation is
    // needed before the next dispatch begins consuming them.
    opt_ir_ssa_work_queue[row] =
        (hash_slot == 0xffffffffu ? 0u : hash_slot) + 1u;
}
