// Validates that structured resolution left one well-formed immediate-
// dominator identity per reachable block. Full dominance-frontier validation
// is added with the tree child relation; this boundary rejects unresolved or
// cross-function parents before declaration-specific SSA work begins.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint edge_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> semantic_function_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrFunction> opt_ir_functions;
StructuredBuffer<uint> opt_ir_immediate_dominator;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint block_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block_id);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block_id >= block_total) return;

    OptIrBlock block = opt_ir_blocks[block_id];
    uint function_total = min(semantic_function_total[0u], gParams.hir_capacity);
    if (block.function_id >= function_total)
    {
        report_structure_failure(block_id);
        return;
    }

    uint dominator = opt_ir_immediate_dominator[block_id];
    uint entry = opt_ir_functions[block.function_id].entry_block;
    bool valid = block_id == entry
        ? dominator == block_id
        : dominator == OPT_IR_DOMINATOR_UNREACHABLE ||
            (dominator < block_total && dominator != block_id &&
             opt_ir_blocks[dominator].function_id == block.function_id &&
             opt_ir_blocks[dominator].position_start < block.position_start);
    if (!valid) report_structure_failure(block_id);
}
