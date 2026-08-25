// Checks the materialized depth relation independently of the binary-lifting
// pass. Unreachable chains remain explicit; every reachable non-entry block
// must be exactly one level below its immediate dominator.

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
StructuredBuffer<uint> opt_ir_dominator_depth;
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

    OptIrBlock block = opt_ir_blocks[block_id];
    OptIrFunction function = opt_ir_functions[block.function_id];
    uint parent = opt_ir_immediate_dominator[block_id];
    uint depth = opt_ir_dominator_depth[block_id];
    bool valid;
    if (block_id == function.entry_block)
        valid = parent == block_id && depth == 0u;
    else if (depth == INVALID)
        valid = parent == OPT_IR_DOMINATOR_UNREACHABLE ||
            (parent < total && opt_ir_dominator_depth[parent] == INVALID);
    else
        valid = parent < total &&
            opt_ir_blocks[parent].function_id == block.function_id &&
            opt_ir_dominator_depth[parent] != INVALID &&
            opt_ir_dominator_depth[parent] + 1u == depth;

    if (!valid) report_structure_failure(block_id);
}
