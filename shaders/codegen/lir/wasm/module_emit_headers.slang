import codegen.lir.wasm.module_common;
import codegen.lir.wasm.host_abi;
import codegen.lir.wasm.module_sections;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint function_capacity; uint artifact_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<WasmModuleLayout> wasm_module_layout;
StructuredBuffer<uint> semantic_lir_string_pool_len;
StructuredBuffer<uint> semantic_lir_string_data;
RWStructuredBuffer<uint> wasm_module_bytes;

static const uint DISPATCH_X_STRIDE = 16776960u;

void emit_leb5(uint start, uint value, uint pos)
{
    if (pos >= start && pos < start + 5u)
        wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos,
                               wasm_module_leb5_byte(value, pos - start));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint pos = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    WasmModuleLayout layout = wasm_module_layout[0u];
    if (layout.status != 0u || pos >= layout.module_length) return;
    if (pos < 8u)
    {
        static const uint header[8] = {0x00u, 0x61u, 0x73u, 0x6du, 0x01u, 0u, 0u, 0u};
        wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, header[pos]);
        return;
    }

    if (pos >= layout.type_section_start && pos < layout.type_entries_start)
    {
        uint rel = pos - layout.type_section_start;
        if (rel == 0u) wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, 1u);
        else if (rel <= 5u) emit_leb5(layout.type_section_start + 1u,
            5u + layout.type_entries_length, pos);
        else emit_leb5(layout.type_section_start + 6u,
            WASM_HOST_TYPE_COUNT + layout.function_count, pos);
        return;
    }
    uint import_section_start = layout.type_entries_start + layout.type_entries_length;
    if (pos >= layout.type_entries_start &&
        pos < layout.type_entries_start + WASM_HOST_TYPE_ENTRIES_LENGTH)
    {
        wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos,
            wasm_host_type_entries_byte(pos - layout.type_entries_start));
        return;
    }
    if (pos >= import_section_start && pos < layout.function_section_start)
    {
        wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos,
            wasm_host_import_section_byte(pos - import_section_start));
        return;
    }
    if (pos >= layout.function_section_start && pos < layout.function_entries_start)
    {
        uint rel = pos - layout.function_section_start;
        if (rel == 0u) wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, 3u);
        else if (rel <= 5u) emit_leb5(layout.function_section_start + 1u,
            5u + layout.function_count * 5u, pos);
        else emit_leb5(layout.function_section_start + 6u, layout.function_count, pos);
        return;
    }
    if (pos >= layout.reserved0 && pos < layout.reserved1)
    {
        wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos,
            wasm_memory_section_byte(pos - layout.reserved0, gParams.reserved0));
        return;
    }
    if (pos >= layout.reserved1 && pos < layout.export_section_start)
    {
        uint bump_start = (semantic_lir_string_pool_len[0u] + 3u) & ~3u;
        wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos,
            wasm_global_section_byte(pos - layout.reserved1, bump_start));
        return;
    }
    if (layout.entrypoint_count == 1u && pos >= layout.export_section_start &&
        pos < layout.code_section_start)
    {
        wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos,
            wasm_export_section_byte(pos - layout.export_section_start,
                WASM_HOST_IMPORT_COUNT + layout.entrypoint_id));
        return;
    }
    if (pos >= layout.code_section_start && pos < layout.code_entries_start)
    {
        uint rel = pos - layout.code_section_start;
        if (rel == 0u) wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, 10u);
        else if (rel <= 5u) emit_leb5(layout.code_section_start + 1u,
            5u + layout.code_entries_length, pos);
        else emit_leb5(layout.code_section_start + 6u, layout.function_count, pos);
        return;
    }
    uint data_start = layout.code_entries_start + layout.code_entries_length;
    uint string_bytes = semantic_lir_string_pool_len[0u];
    if (string_bytes != 0u && pos >= data_start)
    {
        uint rel = pos - data_start;
        if (rel == 0u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 11u);
        else if (rel <= 5u) emit_leb5(data_start + 1u, 18u + string_bytes, pos);
        else if (rel <= 10u) emit_leb5(data_start + 6u, 1u, pos);
        else if (rel == 11u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 0u);
        else if (rel == 12u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 0x41u);
        else if (rel <= 17u) emit_leb5(data_start + 13u, 0u, pos);
        else if (rel == 18u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 0x0bu);
        else if (rel <= 23u) emit_leb5(data_start + 19u, string_bytes, pos);
        else
        {
            uint byte_i = rel - 24u;
            uint value = semantic_lir_string_data[byte_i >> 2u] >>
                ((byte_i & 3u) * 8u);
            wasm_module_store_byte(wasm_module_bytes,
                gParams.artifact_capacity, pos, value);
        }
    }
}
