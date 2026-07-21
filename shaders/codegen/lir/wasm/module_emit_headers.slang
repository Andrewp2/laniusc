import codegen.lir.wasm.module_common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint function_capacity; uint artifact_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<WasmModuleLayout> wasm_module_layout;
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
        else emit_leb5(layout.type_section_start + 6u, layout.function_count, pos);
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
        // memory section: one memory, no maximum, sixteen initial pages.
        static const uint memory_section[5] = {5u, 3u, 1u, 0u, 16u};
        wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos,
                               memory_section[rel]);
        return;
    }
    if (pos >= layout.reserved1 && pos < layout.export_section_start)
    {
        uint rel = pos - layout.reserved1;
        // global section: one mutable i32 bump pointer initialized to zero.
        static const uint global_section[8] =
            {6u, 6u, 1u, 0x7fu, 1u, 0x41u, 0u, 0x0bu};
        wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos,
                               global_section[rel]);
        return;
    }
    if (layout.entrypoint_count == 1u && pos >= layout.export_section_start &&
        pos < layout.code_section_start)
    {
        uint rel = pos - layout.export_section_start;
        if (rel == 0u) wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, 7u);
        else if (rel <= 5u) emit_leb5(layout.export_section_start + 1u, 16u, pos);
        else if (rel <= 10u) emit_leb5(layout.export_section_start + 6u, 1u, pos);
        else if (rel == 11u) wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, 4u);
        else if (rel >= 12u && rel < 16u)
        {
            static const uint name[4] = {0x6du, 0x61u, 0x69u, 0x6eu};
            wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, name[rel - 12u]);
        }
        else if (rel == 16u) wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, 0u);
        else emit_leb5(layout.export_section_start + 17u, layout.entrypoint_id, pos);
        return;
    }
    if (pos >= layout.code_section_start && pos < layout.code_entries_start)
    {
        uint rel = pos - layout.code_section_start;
        if (rel == 0u) wasm_module_store_byte(wasm_module_bytes, gParams.artifact_capacity, pos, 10u);
        else if (rel <= 5u) emit_leb5(layout.code_section_start + 1u,
            5u + layout.code_entries_length, pos);
        else emit_leb5(layout.code_section_start + 6u, layout.function_count, pos);
    }
}
