// Materializes the canonical `(declaration, block)` relation that seeds
// demand-driven SSA construction. Later fixed-point rounds use the same record
// type for transparent blocks that have no declaration-access row.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint access_capacity;
    uint declaration_capacity;
    uint parameter_capacity;
    uint local_capacity;
    uint reserved;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_declaration_block_total;
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_order;
StructuredBuffer<OptIrDeclarationBlock> opt_ir_declaration_blocks;
StructuredBuffer<uint> opt_ir_ssa_demand_seed_flag;
StructuredBuffer<uint> opt_ir_ssa_demand_seed_prefix;
RWStructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.access_capacity;
}

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint canonical_row =
        linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_declaration_block_total[0u],
        gParams.access_capacity);
    if (canonical_row >= total ||
        opt_ir_ssa_demand_seed_flag[canonical_row] == 0u)
        return;

    uint access_total = min(opt_ir_access_total[0u], gParams.access_capacity);
    uint access_start = opt_ir_declaration_blocks[canonical_row].access_start;
    uint access_id = access_start < access_total
        ? opt_ir_access_order[access_start] : gParams.access_capacity;
    uint dense_row = opt_ir_ssa_demand_seed_prefix[canonical_row];
    if (dense_row >= gParams.access_capacity)
        report_capacity(dense_row + 1u);
    else if (access_id >= access_total)
        report_structure_failure(canonical_row);
    else
    {
        OptIrAccessCore access = opt_ir_accesses[access_id];
        OptIrSsaDemand demand;
        demand.declaration = access.subject;
        demand.block = access.block_id;
        opt_ir_ssa_demands[dense_row] = demand;
    }
}
