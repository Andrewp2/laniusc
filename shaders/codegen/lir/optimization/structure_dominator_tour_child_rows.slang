// Inverts the compact dominator-child relation. Each reachable non-root block
// appears exactly once, so every invocation writes a distinct block row.

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
StructuredBuffer<uint> opt_ir_dominator_child_total;
StructuredBuffer<uint> opt_ir_dominator_children;
RWStructuredBuffer<uint> opt_ir_dominator_child_row_by_block;
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
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint child_total = min(opt_ir_dominator_child_total[0u], block_total);
    if (row >= child_total) return;
    uint child = opt_ir_dominator_children[row];
    if (child >= block_total)
    {
        report_structure_failure(row);
        return;
    }
    opt_ir_dominator_child_row_by_block[child] = row;
}
