// Validates exact preorder inversion and parent/child subtree containment.

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
StructuredBuffer<uint> opt_ir_dominator_preorder;
StructuredBuffer<uint> opt_ir_dominator_subtree_end;
StructuredBuffer<uint> opt_ir_block_by_dominator_preorder;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint block)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block >= block_total) return;

    uint parent = opt_ir_immediate_dominator[block];
    uint preorder = opt_ir_dominator_preorder[block];
    uint subtree_end = opt_ir_dominator_subtree_end[block];
    if (parent == OPT_IR_DOMINATOR_UNREACHABLE)
    {
        if (preorder != INVALID || subtree_end != INVALID)
            report_structure_failure(block);
        return;
    }

    uint function_total = min(semantic_function_total[0u],
        gParams.hir_capacity);
    uint function_id = opt_ir_blocks[block].function_id;
    bool valid = parent < block_total && function_id < function_total &&
        preorder < block_total && subtree_end > preorder &&
        opt_ir_block_by_dominator_preorder[preorder] == block;
    OptIrFunction function = valid ? opt_ir_functions[function_id]
        : opt_ir_functions[0u];
    valid = valid && preorder >= function.block_start &&
        subtree_end <= function.block_start + function.block_count;
    if (valid && parent == block)
        valid = function.entry_block == block &&
            preorder == function.block_start;
    else if (valid)
    {
        uint parent_preorder = opt_ir_dominator_preorder[parent];
        uint parent_end = opt_ir_dominator_subtree_end[parent];
        valid = opt_ir_blocks[parent].function_id == function_id &&
            parent_preorder <= preorder && subtree_end <= parent_end &&
            parent_preorder != preorder;
    }
    if (!valid) report_structure_failure(block);
}
