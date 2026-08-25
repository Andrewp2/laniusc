// Independently validates the sparse seeds for demand-driven SSA: each
// canonical row has the expected mark and prefix mapping, and the resulting
// `(declaration, block)` relation is strictly ordered.

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
StructuredBuffer<OptIrReachingDefinitionState>
    opt_ir_reaching_definition_states;
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_order;
StructuredBuffer<OptIrDeclarationBlock> opt_ir_declaration_blocks;
StructuredBuffer<uint> opt_ir_ssa_demand_total;
StructuredBuffer<uint> opt_ir_ssa_demand_seed_flag;
StructuredBuffer<uint> opt_ir_ssa_demand_seed_prefix;
StructuredBuffer<OptIrSsaDemand> opt_ir_ssa_demands;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

bool demand_less(OptIrSsaDemand left, OptIrSsaDemand right)
{
    return left.declaration < right.declaration ||
        (left.declaration == right.declaration && left.block < right.block);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint row_total = min(opt_ir_declaration_block_total[0u],
        gParams.access_capacity);
    if (row >= row_total) return;

    uint demand_total = min(opt_ir_ssa_demand_total[0u],
        gParams.access_capacity);
    bool expected =
        opt_ir_reaching_definition_states[row].incoming_definition ==
            OPT_IR_REACHING_DEFINITION_UNRESOLVED;
    bool valid = opt_ir_ssa_demand_seed_flag[row] == (expected ? 1u : 0u);
    if (expected)
    {
        uint access_total = min(opt_ir_access_total[0u],
            gParams.access_capacity);
        uint access_start = opt_ir_declaration_blocks[row].access_start;
        uint access_id = access_start < access_total
            ? opt_ir_access_order[access_start] : gParams.access_capacity;
        uint dense_row = opt_ir_ssa_demand_seed_prefix[row];
        valid = valid && access_id < access_total && dense_row < demand_total;
        if (valid)
        {
            OptIrAccessCore access = opt_ir_accesses[access_id];
            OptIrSsaDemand demand = opt_ir_ssa_demands[dense_row];
            valid = demand.declaration == access.subject &&
                demand.block == access.block_id;
        }
    }

    if (row < demand_total)
    {
        OptIrSsaDemand demand = opt_ir_ssa_demands[row];
        valid = valid && demand.declaration < gParams.declaration_capacity &&
            demand.block < gParams.block_capacity &&
            (row == 0u || demand_less(opt_ir_ssa_demands[row - 1u], demand));
    }

    if (!valid) report_structure_failure(row);
}
