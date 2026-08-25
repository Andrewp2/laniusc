// Seeds binary lifting over the compact immediate-dominator relation. The
// distance column is accumulated with the ancestor jump so tree depth is
// obtained in logarithmic rounds without a function-owning serial walk.

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
RWStructuredBuffer<OptIrDominatorJump> opt_ir_dominator_depth_link_out;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block_id >= total) return;

    uint parent = opt_ir_immediate_dominator[block_id];
    OptIrDominatorJump link;
    link.ancestor = parent;
    link.distance = parent == block_id ? 0u : parent < total ? 1u : INVALID;
    opt_ir_dominator_depth_link_out[block_id] = link;
}
