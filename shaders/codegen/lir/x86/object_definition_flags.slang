import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> target_function_count;
StructuredBuffer<uint> target_function_index_by_semantic;
RWStructuredBuffer<uint> x86_object_definition_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (function_id >= gParams.function_capacity) return;
    uint count = min(semantic_lir_function_total[0u], gParams.function_capacity);
    uint target_count = min(target_function_count[0u], gParams.function_capacity);
    uint target_index = target_function_index_by_semantic[function_id];
    x86_object_definition_flag[function_id] = function_id < count &&
        semantic_lir_functions[function_id].symbol_local_index != INVALID &&
        target_index != INVALID && target_index < target_count ? 1u : 0u;
}
