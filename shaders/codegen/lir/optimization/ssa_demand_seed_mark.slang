// Marks declaration/block rows whose first read needs a value from the CFG.
// These rows seed backward, demand-driven SSA construction; they are not a
// completed live-in relation.

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
RWStructuredBuffer<uint> opt_ir_ssa_demand_seed_flag;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

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
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint row_total = min(opt_ir_declaration_block_total[0u],
        gParams.access_capacity);
    if (row >= row_total) return;

    uint state = opt_ir_reaching_definition_states[row].incoming_definition;
    bool upward_use = state == OPT_IR_REACHING_DEFINITION_UNRESOLVED;
    bool valid = upward_use || state == OPT_IR_REACHING_DEFINITION_UNUSED;
    opt_ir_ssa_demand_seed_flag[row] = upward_use ? 1u : 0u;
    if (!valid) report_structure_failure(row);
}
