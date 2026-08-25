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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint region_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_region_total[0u], gParams.block_capacity);
    if (region_id >= total) return;

    uint candidate = opt_ir_region_parent_link_in[region_id];
    if (candidate >= total)
    {
        opt_ir_region_parent_link_out[region_id] = INVALID;
        return;
    }
    OptIrRegion child = opt_ir_regions[region_id];
    OptIrRegion possible_parent = opt_ir_regions[candidate];
    bool encloses = possible_parent.function_id == child.function_id &&
        possible_parent.position_start < child.position_start &&
        possible_parent.position_end > child.position_end;
    opt_ir_region_parent_link_out[region_id] = encloses
        ? candidate : opt_ir_region_parent_link_in[candidate];
}
