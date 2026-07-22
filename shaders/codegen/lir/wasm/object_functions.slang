import codegen.lowering_ir;
import gpu_index;

struct ObjectIdentity { uint library_id; uint unit_id; uint reserved0; uint reserved1; };
struct Params { uint target_capacity; uint function_capacity; uint artifact_capacity; uint reserved; };
ConstantBuffer<ObjectIdentity> gIdentity;
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<WasmLirFunction> wasm_lir_functions;
StructuredBuffer<uint> wasm_type_entry_length;
StructuredBuffer<uint> wasm_type_entry_offset;
StructuredBuffer<uint> wasm_code_entry_length;
StructuredBuffer<uint> wasm_code_entry_offset;
StructuredBuffer<uint> wasm_object_symbol_total;
StructuredBuffer<uint> wasm_object_definition_flag;
StructuredBuffer<uint> wasm_object_definition_prefix;
RWStructuredBuffer<WasmObjectFunctionRow> wasm_object_functions;
RWStructuredBuffer<WasmObjectDefinitionRow> wasm_object_definitions;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint function_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint count = min(semantic_lir_function_total[0u], gParams.function_capacity);
    if (function_id >= count) return;
    SemanticLirFunction semantic = semantic_lir_functions[function_id];
    WasmLirFunction function = wasm_lir_functions[function_id];
    bool defined = wasm_object_definition_flag[function_id] != 0u;
    uint definition_index = wasm_object_definition_prefix[function_id];

    WasmObjectFunctionRow out_function;
    out_function.type_byte_start = wasm_type_entry_offset[function_id];
    out_function.type_byte_len = wasm_type_entry_length[function_id];
    out_function.body_byte_start = wasm_code_entry_offset[function_id];
    out_function.body_byte_len = wasm_code_entry_length[function_id];
    out_function.symbol_index = defined
        ? wasm_object_symbol_total[0u] + definition_index : INVALID;
    out_function.flags = function.flags;
    wasm_object_functions[function_id] = out_function;

    if (defined)
    {
        WasmObjectDefinitionRow definition;
        definition.library_id = gIdentity.library_id;
        definition.unit_id = gIdentity.unit_id;
        definition.local_index = semantic.symbol_local_index;
        definition.function_index = function_id;
        definition.size = function.body_byte_count;
        definition.flags = semantic.symbol_flags;
        definition.reserved0 = 0u;
        definition.reserved1 = 0u;
        wasm_object_definitions[definition_index] = definition;
    }
}
