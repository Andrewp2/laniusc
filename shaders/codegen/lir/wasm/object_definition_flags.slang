import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<uint> wasm_object_definition_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.function_capacity) return;
    uint count = min(semantic_lir_function_total[0u], gParams.function_capacity);
    wasm_object_definition_flag[row] = row < count &&
        semantic_lir_functions[row].symbol_local_index != INVALID ? 1u : 0u;
}
