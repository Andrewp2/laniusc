// Doubles the immediate-dominator distance represented by each compact link.

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
StructuredBuffer<OptIrDominatorJump> opt_ir_dominator_depth_link_in;
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

    OptIrDominatorJump link = opt_ir_dominator_depth_link_in[block_id];
    if (link.ancestor >= total || link.ancestor == block_id)
    {
        opt_ir_dominator_depth_link_out[block_id] = link;
        return;
    }

    OptIrDominatorJump parent =
        opt_ir_dominator_depth_link_in[link.ancestor];
    OptIrDominatorJump result;
    result.ancestor = parent.ancestor;
    result.distance = link.distance == INVALID || parent.distance == INVALID ||
        link.distance > INVALID - 1u - parent.distance
        ? INVALID : link.distance + parent.distance;
    opt_ir_dominator_depth_link_out[block_id] = result;
}
