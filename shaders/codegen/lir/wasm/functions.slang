import codegen.lowering_ir;
import codegen.lir.wasm.host_abi;
import gpu_index;

struct Params { uint function_capacity; uint param_capacity; uint local_capacity; uint n_tokens; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> semantic_lir_param_total;
StructuredBuffer<uint> wasm_param_prefix;
StructuredBuffer<uint> wasm_param_value_total;
StructuredBuffer<uint> semantic_lir_local_total;
StructuredBuffer<uint> wasm_local_prefix;
StructuredBuffer<uint> wasm_local_value_total;
RWStructuredBuffer<WasmLirFunction> wasm_lir_functions;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint range_total(uint start, uint count, uint family_count,
                 StructuredBuffer<uint> prefix, StructuredBuffer<uint> total)
{
    if (count == 0u || start == INVALID || start >= family_count) return 0u;
    uint end = min(start + count, family_count);
    uint before = prefix[start];
    uint after = end < family_count ? prefix[end] : total[0u];
    return after - before;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint function_count = min(semantic_lir_function_total[0u], gParams.function_capacity);
    if (function_id >= function_count) return;
    SemanticLirFunction source = semantic_lir_functions[function_id];
    uint param_count = min(semantic_lir_param_total[0u], gParams.param_capacity);
    uint local_count = min(semantic_lir_local_total[0u], gParams.local_capacity);
    WasmLirFunction result;
    result.semantic_function = function_id;
    result.type_index = WASM_HOST_TYPE_COUNT + function_id;
    result.param_value_count = range_total(
        source.param_start, source.param_count, param_count,
        wasm_param_prefix, wasm_param_value_total);
    result.local_value_count = range_total(
        source.local_start, source.local_count, local_count,
        wasm_local_prefix, wasm_local_value_total);
    result.body_instruction_start = 0u;
    result.body_instruction_count = 0u;
    result.body_byte_start = 0u;
    result.body_byte_count = 0u;
    result.flags = source.flags;
    result.result_type = source.result_type;
    result.param_start = source.param_start;
    result.param_count = source.param_count;
    result.local_start = source.local_start;
    result.local_count = source.local_count;
    wasm_lir_functions[function_id] = result;
}
