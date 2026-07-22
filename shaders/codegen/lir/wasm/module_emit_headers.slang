import codegen.lir.wasm.module_common;
import codegen.lir.wasm.host_abi;
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
        uint rel = pos - layout.reserved0;
        if (rel == 0u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 5u);
        else if (rel <= 5u) emit_leb5(layout.reserved0 + 1u, 11u, pos);
        else if (rel <= 10u) emit_leb5(layout.reserved0 + 6u, 1u, pos);
        else if (rel == 11u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 0u);
        else emit_leb5(layout.reserved0 + 12u, gParams.reserved0, pos);
        return;
    }
    if (pos >= layout.reserved1 && pos < layout.export_section_start)
    {
        uint rel = pos - layout.reserved1;
        uint bump_start = (semantic_lir_string_pool_len[0u] + 3u) & ~3u;
        if (rel == 0u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 6u);
        else if (rel == 1u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 10u);
        else if (rel == 2u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 1u);
        else if (rel == 3u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 0x7fu);
        else if (rel == 4u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 1u);
        else if (rel == 5u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 0x41u);
        else if (rel <= 10u) emit_leb5(layout.reserved1 + 6u, bump_start, pos);
        else wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 0x0bu);
        return;
    }
    if (layout.entrypoint_count == 1u && pos >= layout.export_section_start &&
        pos < layout.code_section_start)
    {
        uint rel = pos - layout.export_section_start;
        if (rel == 0u) wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, 7u);
        else if (rel <= 5u) emit_leb5(layout.export_section_start + 1u, 25u, pos);
        else if (rel <= 10u) emit_leb5(layout.export_section_start + 6u, 2u, pos);
        else if (rel == 11u) wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, 4u);
        else if (rel >= 12u && rel < 16u)
        {
            static const uint name[4] = {0x6du, 0x61u, 0x69u, 0x6eu};
            wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, name[rel - 12u]);
        }
        else if (rel == 16u) wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, 0u);
        else if (rel <= 21u)
            emit_leb5(layout.export_section_start + 17u,
                WASM_HOST_IMPORT_COUNT + layout.entrypoint_id, pos);
        else if (rel == 22u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 6u);
        else if (rel >= 23u && rel < 29u)
        {
            static const uint memory_name[6] =
                {0x6du, 0x65u, 0x6du, 0x6fu, 0x72u, 0x79u};
            wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos,
                memory_name[rel - 23u]);
        }
        else if (rel == 29u) wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 2u);
        else wasm_module_store_byte(wasm_module_bytes,
            gParams.artifact_capacity, pos, 0u);
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
