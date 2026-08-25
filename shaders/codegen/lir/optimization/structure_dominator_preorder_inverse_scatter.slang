// Inverts reachable preorder identities and reports duplicate assignments.

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
StructuredBuffer<uint> opt_ir_dominator_preorder;
RWStructuredBuffer<uint> opt_ir_block_by_dominator_preorder;
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
    uint total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block >= total) return;
    uint preorder = opt_ir_dominator_preorder[block];
    if (preorder == INVALID) return;
    if (preorder >= total)
    {
        report_structure_failure(block);
        return;
    }
    uint previous;
    InterlockedCompareExchange(
        opt_ir_block_by_dominator_preorder[preorder], INVALID,
        block, previous);
    if (previous != INVALID) report_structure_failure(block);
}
