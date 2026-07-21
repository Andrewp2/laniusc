import codegen.lowering_ir;
import gpu_index;

struct Params { uint function_capacity; uint param_capacity; uint local_capacity; uint n_tokens; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_param_total;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
RWStructuredBuffer<uint> wasm_param_width;

static const uint TY_STRING = 7u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.param_capacity) return;
    uint count = min(semantic_lir_param_total[0u], gParams.param_capacity);
    wasm_param_width[row] = row < count && semantic_lir_params[row].type_id == TY_STRING ? 2u
        : row < count ? 1u : 0u;
}
