// One pointer-jump round for the previous enclosing interval relation.

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
StructuredBuffer<uint> opt_ir_region_total;
StructuredBuffer<OptIrRegion> opt_ir_regions;
StructuredBuffer<uint> opt_ir_region_parent_link_in;
RWStructuredBuffer<uint> opt_ir_region_parent_link_out;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint REGION_PARENT_HOPS = 32u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint region_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_region_total[0u], gParams.block_capacity);
    if (region_id >= total) return;

    // A candidate that does not enclose this region ends before it starts,
    // and so do the regions its own link skipped; following links never
    // passes the parent. Once a candidate's link has converged to its parent
    // a round climbs only one level, so a later sibling of a deeply nested
    // chain would need one round per level: each round walks a bounded
    // number of links instead.
    OptIrRegion child = opt_ir_regions[region_id];
    uint candidate = opt_ir_region_parent_link_in[region_id];
    bool encloses = false;
    for (uint hop = 0u; hop < REGION_PARENT_HOPS && candidate < total && !encloses; hop += 1u)
    {
        OptIrRegion possible_parent = opt_ir_regions[candidate];
        encloses = possible_parent.function_id == child.function_id &&
            possible_parent.position_start < child.position_start &&
            possible_parent.position_end > child.position_end;
        if (!encloses) candidate = opt_ir_region_parent_link_in[candidate];
    }
    opt_ir_region_parent_link_out[region_id] = candidate < total ? candidate : INVALID;
}
