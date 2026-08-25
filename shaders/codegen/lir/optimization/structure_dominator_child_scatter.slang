// Scatters dense child block IDs into their immediate dominator's range.

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
StructuredBuffer<uint> opt_ir_immediate_dominator;
RWStructuredBuffer<uint> opt_ir_dominator_child_cursor;
RWStructuredBuffer<uint> opt_ir_dominator_children;
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
    uint total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block_id >= total) return;

    uint dominator = opt_ir_immediate_dominator[block_id];
    if (dominator == block_id || dominator == OPT_IR_DOMINATOR_UNREACHABLE)
        return;
    if (dominator >= total)
    {
        report_structure_failure(block_id);
        return;
    }

    uint row;
    InterlockedAdd(opt_ir_dominator_child_cursor[dominator], 1u, row);
    if (row >= total)
    {
        report_structure_failure(block_id);
        return;
    }
    opt_ir_dominator_children[row] = block_id;
}
