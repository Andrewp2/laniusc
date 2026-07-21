import codegen.lir.wasm.module_common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint function_capacity; uint artifact_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> wasm_lir_function_total;
StructuredBuffer<WasmLirFunction> wasm_lir_functions;
RWStructuredBuffer<uint> wasm_type_entry_length;
RWStructuredBuffer<uint> wasm_code_entry_length;
RWStructuredBuffer<uint> wasm_module_entrypoint_state;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint count = min(wasm_lir_function_total[0u], gParams.function_capacity);
    if (function_id >= gParams.function_capacity) return;
    if (function_id >= count)
    {
        wasm_type_entry_length[function_id] = 0u;
        wasm_code_entry_length[function_id] = 0u;
        return;
    }
    WasmLirFunction function = wasm_lir_functions[function_id];
    uint results = wasm_module_result_count(function.result_type);
    // 0x60, padded parameter count, expanded value types, padded result count,
    // and expanded result value types.
    wasm_type_entry_length[function_id] = 11u + function.param_value_count + results;
    // Padded body size, padded local-group count, one six-byte declaration per
    // semantic local, two target-private six-byte temporary declarations,
    // instruction bytes, the function-end opcode, and a non-void
    // `unreachable` fallthrough guard when a result is required.
    wasm_code_entry_length[function_id] = 23u + function.local_count * 6u +
        function.body_byte_count + results;
    if ((function.flags & WASM_MODULE_FUNCTION_ENTRYPOINT) != 0u)
    {
        uint ignored;
        InterlockedAdd(wasm_module_entrypoint_state[0u], 1u, ignored);
        InterlockedMin(wasm_module_entrypoint_state[1u], function_id, ignored);
    }
}
