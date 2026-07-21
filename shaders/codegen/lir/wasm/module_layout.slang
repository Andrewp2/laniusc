import codegen.lir.wasm.module_common;
import codegen.lowering_ir;

struct Params { uint function_capacity; uint artifact_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> wasm_lir_function_total;
StructuredBuffer<uint> wasm_type_entries_length;
StructuredBuffer<uint> wasm_code_entries_length;
StructuredBuffer<uint> wasm_module_entrypoint_state;
RWStructuredBuffer<WasmModuleLayout> wasm_module_layout;
RWStructuredBuffer<uint> wasm_module_length;
RWStructuredBuffer<LoweringStatus> lowering_status;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    WasmModuleLayout layout;
    layout.function_count = min(wasm_lir_function_total[0u], gParams.function_capacity);
    layout.entrypoint_count = wasm_module_entrypoint_state[0u];
    layout.entrypoint_id = wasm_module_entrypoint_state[1u];
    layout.status = layout.entrypoint_count > 1u ? 1u : 0u;
    if (layout.entrypoint_count > 1u)
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_MULTIPLE_ENTRYPOINTS);
    layout.type_entries_length = wasm_type_entries_length[0u];
    layout.code_entries_length = wasm_code_entries_length[0u];
    layout.type_section_start = 8u;
    layout.type_entries_start = layout.type_section_start + 11u;
    layout.function_section_start = layout.type_entries_start + layout.type_entries_length;
    layout.function_entries_start = layout.function_section_start + 11u;
    uint function_section_end = layout.function_entries_start + layout.function_count * 5u;
    layout.reserved0 = function_section_end;
    layout.reserved1 = layout.reserved0 + 5u;
    layout.export_section_start = layout.reserved1 + 8u;
    uint export_length = layout.entrypoint_count == 1u ? 22u : 0u;
    layout.code_section_start = layout.export_section_start + export_length;
    layout.code_entries_start = layout.code_section_start + 11u;
    layout.module_length = layout.code_entries_start + layout.code_entries_length;
    if (layout.module_length > gParams.artifact_capacity)
    {
        layout.status = 2u;
        InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_ARTIFACT_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity, layout.module_length);
        InterlockedMin(lowering_status[0u].available_capacity, gParams.artifact_capacity);
    }
    wasm_module_layout[0u] = layout;
    wasm_module_length[0u] = layout.module_length;
}
