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
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> semantic_function_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
RWStructuredBuffer<OptIrFunction> opt_ir_functions;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(gParams.block_capacity, opt_ir_block_total[0u]);
    if (block_id >= block_total) return;

    OptIrBlock block = opt_ir_blocks[block_id];
    uint function_total = min(gParams.hir_capacity, semantic_function_total[0u]);
    if (block.function_id >= function_total)
    {
        uint ignored;
        InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
            LOWERING_DIAGNOSTIC_NONE,
            LOWERING_DIAGNOSTIC_OPT_STRUCTURE_FUNCTION_REDUCE, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
        InterlockedMin(lowering_status[0u].first_unsupported_opt_row,
            block.terminator);
        return;
    }
    uint node_total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    uint node_end = block_id + 1u < block_total &&
        opt_ir_blocks[block_id + 1u].function_id == block.function_id
        ? opt_ir_blocks[block_id + 1u].position_start : node_total;

    InterlockedMin(opt_ir_functions[block.function_id].node_start,
        block.position_start);
    InterlockedMax(opt_ir_functions[block.function_id].node_count, node_end);
    InterlockedMin(opt_ir_functions[block.function_id].block_start, block_id);
    InterlockedMax(opt_ir_functions[block.function_id].block_count,
        block_id + 1u);
    InterlockedMin(opt_ir_functions[block.function_id].entry_block, block_id);
    // region_count is not observable until this three-pass construction is
    // complete. Use it as the block-membership count so finalization can prove
    // that each function owns one contiguous block range, then reset it to the
    // currently empty region count.
    InterlockedAdd(opt_ir_functions[block.function_id].region_count, 1u);
}
