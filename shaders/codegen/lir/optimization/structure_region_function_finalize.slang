// Converts temporary region ends into counts and validates per-function
// contiguity in dense opening order.

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
StructuredBuffer<OptIrRegion> opt_ir_regions;
RWStructuredBuffer<OptIrFunction> opt_ir_functions;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint function_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, function_id);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint function_total = min(semantic_function_total[0u], gParams.hir_capacity);
    if (function_id >= function_total) return;

    uint region_total = min(opt_ir_region_total[0u], gParams.block_capacity);
    OptIrFunction function = opt_ir_functions[function_id];
    if (function.region_start == INVALID)
    {
        if (function.region_count != 0u) report_structure_failure(function_id);
        function.region_start = 0u;
        function.region_count = 0u;
        opt_ir_functions[function_id] = function;
        return;
    }

    uint end = function.region_count;
    bool valid = function.region_start < end && end <= region_total &&
        opt_ir_regions[function.region_start].function_id == function_id &&
        opt_ir_regions[end - 1u].function_id == function_id;
    if (!valid)
    {
        report_structure_failure(function_id);
        function.region_count = 0u;
    }
    else
        function.region_count = end - function.region_start;
    opt_ir_functions[function_id] = function;
}
