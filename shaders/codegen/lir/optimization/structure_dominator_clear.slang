// Reuses the predecessor-count column for forward-predecessor counts after
// the compact reverse CFG has been validated. Immediate dominators may alias
// the now-dead predecessor scatter cursor in the phase-colored workspace.

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
RWStructuredBuffer<uint> opt_ir_forward_predecessor_count_by_block;
RWStructuredBuffer<uint> opt_ir_immediate_dominator;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block_id >= total) return;
    opt_ir_forward_predecessor_count_by_block[block_id] = 0u;
    opt_ir_immediate_dominator[block_id] = OPT_IR_DOMINATOR_INVALID;
}
