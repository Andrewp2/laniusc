import codegen.lowering_ir;
import gpu_index;
import primitive_types;

struct Params { uint function_capacity; uint param_capacity; uint local_capacity; uint n_tokens; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_param_total;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
RWStructuredBuffer<uint> wasm_param_width;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint TY_STRING = 7u;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.param_capacity) return;
    uint count = min(semantic_lir_param_total[0u], gParams.param_capacity);
    if (row < count && semantic_lir_params[row].type_id == SCALAR_F64)
    {
        // Check declarations even when the value is unused and emits no row.
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
        uint function_id = semantic_lir_params[row].function_id;
        uint functions = min(semantic_lir_function_total[0u], gParams.function_capacity);
        if (function_id < functions)
            InterlockedMin(lowering_status[0u].first_unsupported_hir,
                semantic_lir_functions[function_id].hir_function);
    }
    wasm_param_width[row] = row < count && semantic_lir_params[row].type_id == TY_STRING ? 2u
        : row < count ? 1u : 0u;
}
