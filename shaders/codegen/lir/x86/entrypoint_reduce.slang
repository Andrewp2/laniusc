import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint token_capacity; uint function_capacity; uint artifact_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<uint> x86_entrypoint_state;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint FUNCTION_ENTRYPOINT = 1u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint count = min(gParams.function_capacity, semantic_lir_function_total[0u]);
    if (function_id >= count) return;
    if ((semantic_lir_functions[function_id].flags & FUNCTION_ENTRYPOINT) != 0u)
    {
        InterlockedAdd(x86_entrypoint_state[0u], 1u);
        InterlockedMin(x86_entrypoint_state[1u], function_id);
    }
}
