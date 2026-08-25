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
StructuredBuffer<SemanticLirFunction> semantic_functions;
RWStructuredBuffer<OptIrFunction> opt_ir_functions;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.hir_capacity, semantic_function_total[0u]);
    if (function_id >= total) return;

    OptIrFunction function;
    function.node_start = INVALID;
    function.node_count = 0u;
    function.block_start = INVALID;
    function.block_count = 0u;
    function.entry_block = INVALID;
    function.flags = semantic_functions[function_id].flags;
    function.region_start = 0u;
    function.region_count = 0u;
    opt_ir_functions[function_id] = function;
}
