import codegen.lowering_ir;
import gpu_index;

struct Params { uint function_capacity; uint target_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_function_count;
StructuredBuffer<TargetLirFunction> target_functions;
StructuredBuffer<uint> target_byte_length;
StructuredBuffer<uint> target_byte_offset;
RWStructuredBuffer<WasmLirFunction> wasm_lir_functions;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint body_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint body_count = min(target_function_count[0u], gParams.function_capacity);
    if (body_row >= body_count) return;
    TargetLirFunction body = target_functions[body_row];
    if (body.function_id >= gParams.function_capacity) return;

    uint start = min(body.instruction_start, gParams.target_capacity);
    uint count = min(body.instruction_count, gParams.target_capacity - start);
    WasmLirFunction function = wasm_lir_functions[body.function_id];
    function.body_instruction_start = start;
    function.body_instruction_count = count;
    function.body_byte_start = count == 0u ? 0u : target_byte_offset[start];
    if (count == 0u)
    {
        function.body_byte_count = 0u;
    }
    else
    {
        uint last = start + count - 1u;
        function.body_byte_count = target_byte_offset[last] + target_byte_length[last] -
            function.body_byte_start;
    }
    wasm_lir_functions[body.function_id] = function;
}
