// Publishes parent identities and reduces contiguous function region ranges.

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
StructuredBuffer<uint> opt_ir_region_total;
StructuredBuffer<uint> semantic_function_total;
StructuredBuffer<uint> opt_ir_region_parent_link;
RWStructuredBuffer<OptIrRegion> opt_ir_regions;
RWStructuredBuffer<OptIrFunction> opt_ir_functions;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint region_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, region_id);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint region_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_region_total[0u], gParams.block_capacity);
    if (region_id >= total) return;

    OptIrRegion region = opt_ir_regions[region_id];
    uint function_total = min(semantic_function_total[0u], gParams.hir_capacity);
    uint parent = opt_ir_region_parent_link[region_id];
    bool valid = region.function_id < function_total &&
        region.position_start < region.position_end;
    if (parent != INVALID)
    {
        valid = valid && parent < region_id && parent < total;
        if (valid)
        {
            OptIrRegion parent_region = opt_ir_regions[parent];
            valid = parent_region.function_id == region.function_id &&
                parent_region.position_start < region.position_start &&
                parent_region.position_end > region.position_end;
        }
    }
    if (!valid)
    {
        report_structure_failure(region_id);
        return;
    }

    region.parent_region = parent;
    opt_ir_regions[region_id] = region;
    InterlockedMin(opt_ir_functions[region.function_id].region_start, region_id);
    InterlockedMax(opt_ir_functions[region.function_id].region_count, region_id + 1u);
}
