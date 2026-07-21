import codegen.lowering_ir;
import gpu_index;

struct Params { uint function_capacity; uint param_capacity; uint local_capacity; uint n_tokens; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_param_total;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> wasm_param_prefix;
StructuredBuffer<uint> semantic_lir_local_total;
StructuredBuffer<SemanticLirLocal> semantic_lir_locals;
StructuredBuffer<uint> wasm_local_prefix;
StructuredBuffer<WasmLirFunction> wasm_lir_functions;
RWStructuredBuffer<uint> wasm_local_index_by_decl_token;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint param_count = min(semantic_lir_param_total[0u], gParams.param_capacity);
    if (row < param_count)
    {
        SemanticLirParam param = semantic_lir_params[row];
        if (param.function_id < gParams.function_capacity &&
            param.declaration_id != INVALID && param.declaration_id < gParams.n_tokens)
        {
            WasmLirFunction function = wasm_lir_functions[param.function_id];
            wasm_local_index_by_decl_token[param.declaration_id] =
                wasm_param_prefix[row] - wasm_param_prefix[function.param_start];
        }
    }

    uint local_count = min(semantic_lir_local_total[0u], gParams.local_capacity);
    if (row < local_count)
    {
        SemanticLirLocal local = semantic_lir_locals[row];
        if (local.function_id < gParams.function_capacity &&
            local.declaration_id != INVALID && local.declaration_id < gParams.n_tokens)
        {
            WasmLirFunction function = wasm_lir_functions[local.function_id];
            wasm_local_index_by_decl_token[local.declaration_id] = function.param_value_count +
                wasm_local_prefix[row] - wasm_local_prefix[function.local_start];
        }
    }
}
