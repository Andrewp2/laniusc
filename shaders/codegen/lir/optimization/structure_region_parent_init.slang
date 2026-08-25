// Starts the previous-greater interval relation from the immediately preceding
// region in opening order. Pointer jumping skips closed siblings in parallel.

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
RWStructuredBuffer<uint> opt_ir_region_parent_link_a;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint region_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_region_total[0u], gParams.block_capacity);
    if (region_id >= total) return;
    opt_ir_region_parent_link_a[region_id] = region_id > 0u &&
        opt_ir_regions[region_id - 1u].function_id ==
            opt_ir_regions[region_id].function_id
        ? region_id - 1u : INVALID;
}
