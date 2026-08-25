// Adds every half-open region interval to a range-max segment tree. Dense
// region IDs follow opening position, so the maximum active ID is exactly the
// innermost region at a point. Closing labels are excluded and therefore
// inherit their parent region.

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
RWStructuredBuffer<uint> opt_ir_region_ownership_tree;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint region_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_region_total[0u], gParams.block_capacity);
    if (region_id >= total) return;

    OptIrRegion region = opt_ir_regions[region_id];
    uint left = min(region.position_start, gParams.semantic_capacity) +
        gParams.semantic_capacity;
    uint right = min(region.position_end, gParams.semantic_capacity) +
        gParams.semantic_capacity;
    uint encoded = region_id + 1u;
    while (left < right)
    {
        if ((left & 1u) != 0u)
            InterlockedMax(opt_ir_region_ownership_tree[left++], encoded);
        if ((right & 1u) != 0u)
            InterlockedMax(opt_ir_region_ownership_tree[--right], encoded);
        left >>= 1u;
        right >>= 1u;
    }
}
