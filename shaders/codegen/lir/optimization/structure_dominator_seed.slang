// Finalizes the exact base of the dominator relation. Only blocks with two or
// more forward predecessors remain unresolved; later GPU rounds intersect
// those predecessor dominator paths. This keeps the required persistent state
// at one word per CFG block.

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
StructuredBuffer<uint> opt_ir_forward_predecessor_count_by_block;
RWStructuredBuffer<uint> opt_ir_immediate_dominator;
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

    OptIrFunction function = opt_ir_functions[block.function_id];
    uint count = opt_ir_forward_predecessor_count_by_block[block_id];
    uint candidate = opt_ir_immediate_dominator[block_id];
    if (block_id == function.entry_block)
    {
        if (count != 0u) report_structure_failure(block_id);
        opt_ir_immediate_dominator[block_id] = block_id;
        return;
    }
    if (count == 0u)
    {
        opt_ir_immediate_dominator[block_id] = OPT_IR_DOMINATOR_UNREACHABLE;
        return;
    }
    if (count > 1u)
    {
        opt_ir_immediate_dominator[block_id] = OPT_IR_DOMINATOR_UNRESOLVED;
        return;
    }

    bool valid = candidate < block_total &&
        opt_ir_blocks[candidate].function_id == block.function_id &&
        opt_ir_blocks[candidate].position_start < block.position_start;
    if (!valid)
    {
        report_structure_failure(block_id);
        opt_ir_immediate_dominator[block_id] = OPT_IR_DOMINATOR_UNRESOLVED;
    }
}
