import codegen.lir.wasm.module_common;
import codegen.lir.wasm.host_abi;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint function_capacity; uint artifact_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> wasm_lir_function_total;
StructuredBuffer<WasmLirFunction> wasm_lir_functions;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<SemanticLirLocal> semantic_lir_locals;
StructuredBuffer<uint> wasm_type_entry_offset;
StructuredBuffer<uint> wasm_code_entry_offset;
StructuredBuffer<uint> wasm_body_bytes;
StructuredBuffer<WasmModuleLayout> wasm_module_layout;
RWStructuredBuffer<uint> wasm_module_bytes;

static const uint DISPATCH_X_STRIDE = 16776960u;

void store(uint pos, uint value)
{
    wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, value);
}

void store_leb5(uint pos, uint value)
{
    for (uint i = 0u; i < 5u; i += 1u) store(pos + i, wasm_module_leb5_byte(value, i));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint count = min(wasm_lir_function_total[0u], gParams.function_capacity);
    WasmModuleLayout layout = wasm_module_layout[0u];
    if (layout.status != 0u || function_id >= count) return;
    WasmLirFunction function = wasm_lir_functions[function_id];

    uint type_pos = layout.type_entries_start + WASM_HOST_TYPE_ENTRIES_LENGTH +
        wasm_type_entry_offset[function_id];
    store(type_pos, 0x60u);
    store_leb5(type_pos + 1u, function.param_value_count);
    uint value_pos = type_pos + 6u;
    for (uint row = 0u; row < function.param_count; row += 1u)
    {
        SemanticLirParam param = semantic_lir_params[function.param_start + row];
        uint width = param.type_id == WASM_MODULE_TY_STRING ? 2u : 1u;
        uint value_type = wasm_module_value_type(param.type_id);
        for (uint value = 0u; value < width; value += 1u) store(value_pos++, value_type);
    }
    uint result_count = wasm_module_result_count(function.result_type);
    store_leb5(value_pos, result_count);
    value_pos += 5u;
    for (uint value = 0u; value < result_count; value += 1u)
        store(value_pos++, wasm_module_value_type(function.result_type));

    uint function_pos = layout.function_entries_start + function_id * 5u;
    store_leb5(function_pos, function.type_index);

    uint code_pos = layout.code_entries_start + wasm_code_entry_offset[function_id];
    uint body_content_length = 17u + function.local_count * 6u +
        function.body_byte_count + 1u + result_count;
    store_leb5(code_pos, body_content_length);
    store_leb5(code_pos + 5u, function.local_count + 2u);
    uint local_pos = code_pos + 10u;
    for (uint row = 0u; row < function.local_count; row += 1u)
    {
        SemanticLirLocal local = semantic_lir_locals[function.local_start + row];
        uint width = local.type_id == WASM_MODULE_TY_STRING ? 2u : 1u;
        store_leb5(local_pos, width);
        store(local_pos + 5u, wasm_module_value_type(local.type_id));
        local_pos += 6u;
    }
    // Target-private typed temporaries support parallel aggregate lowering
    // without exposing source declarations or serializing element families.
    store_leb5(local_pos, 1u);
    store(local_pos + 5u, WASM_MODULE_I32);
    local_pos += 6u;
    store_leb5(local_pos, 1u);
    store(local_pos + 5u, WASM_MODULE_F32);
    local_pos += 6u;
    for (uint byte_i = 0u; byte_i < function.body_byte_count; byte_i += 1u)
        store(local_pos + byte_i,
              wasm_module_load_byte(wasm_body_bytes, function.body_byte_start + byte_i));
    uint footer_pos = local_pos + function.body_byte_count;
    // A structured if whose every arm returns can still leave the enclosing
    // function validator at a reachable merge. Trap any impossible non-void
    // fallthrough rather than synthesizing a language value.
    if (result_count != 0u) store(footer_pos++, 0x00u);
    store(footer_pos, 0x0bu);
}
