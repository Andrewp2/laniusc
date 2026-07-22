import codegen.lir.wasm.module_common;
import codegen.lir.wasm.host_abi;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> wasm_type_entries_length;
StructuredBuffer<uint> wasm_code_entries_length;
StructuredBuffer<WasmModuleLayout> wasm_module_layout;
StructuredBuffer<uint> wasm_module_bytes;
RWStructuredBuffer<uint> wasm_object_type_bytes;
RWStructuredBuffer<uint> wasm_object_body_bytes;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint byte_i = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (byte_i >= gParams.artifact_capacity) return;
    WasmModuleLayout layout = wasm_module_layout[0u];
    uint type_len = min(wasm_type_entries_length[0u], gParams.artifact_capacity);
    uint body_len = min(wasm_code_entries_length[0u], gParams.artifact_capacity);
    if (byte_i < type_len)
    {
        uint source = layout.type_entries_start + WASM_HOST_TYPE_ENTRIES_LENGTH + byte_i;
        wasm_module_store_byte(wasm_object_type_bytes, gParams.artifact_capacity, byte_i,
            wasm_module_load_byte(wasm_module_bytes, source));
    }
    if (byte_i < body_len)
    {
        uint source = layout.code_entries_start + byte_i;
        wasm_module_store_byte(wasm_object_body_bytes, gParams.artifact_capacity, byte_i,
            wasm_module_load_byte(wasm_module_bytes, source));
    }
}
