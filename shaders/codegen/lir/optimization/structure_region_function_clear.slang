// Clears only the region range fields after block/function construction.

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
StructuredBuffer<uint> semantic_function_total;
RWStructuredBuffer<OptIrFunction> opt_ir_functions;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(semantic_function_total[0u], gParams.hir_capacity);
    if (function_id >= total) return;
    opt_ir_functions[function_id].region_start = INVALID;
    opt_ir_functions[function_id].region_count = 0u;
}
