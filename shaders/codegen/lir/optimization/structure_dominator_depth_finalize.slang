// Materializes one compact depth word per block. Dominance queries later use
// this depth to align sparse candidate pairs before batched parent jumping;
// no source-order or dominator-preorder assumption is required.

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
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrFunction> opt_ir_functions;
StructuredBuffer<uint> opt_ir_immediate_dominator;
StructuredBuffer<OptIrDominatorJump> opt_ir_dominator_depth_link;
RWStructuredBuffer<uint> opt_ir_dominator_depth;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
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
    uint total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block_id >= total) return;

    OptIrDominatorJump link = opt_ir_dominator_depth_link[block_id];
    OptIrBlock block = opt_ir_blocks[block_id];
    OptIrFunction function = opt_ir_functions[block.function_id];
    bool reachable = link.ancestor < total &&
        opt_ir_immediate_dominator[link.ancestor] == link.ancestor &&
        link.distance != INVALID;
    uint depth = reachable ? link.distance : INVALID;
    opt_ir_dominator_depth[block_id] = depth;

    bool valid = block_id == function.entry_block
        ? link.ancestor == block_id && depth == 0u
        : depth == INVALID || (link.ancestor == function.entry_block &&
            depth > 0u);
    if (!valid)
        report_structure_failure(block_id);
}
