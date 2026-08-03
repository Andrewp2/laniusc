import codegen.wasm.link.common;
import codegen.lir.wasm.host_abi;
import codegen.lir.wasm.module_sections;
StructuredBuffer<LinkRelocation> link_relocation;
RWStructuredBuffer<uint> out_words;
void write_byte(uint pos, uint value)
{
    if (pos < gLink.output_page_base || pos - gLink.output_page_base >= gLink.output_page_len)
        return;
    pos -= gLink.output_page_base;
    uint word_i = pos >> 2u; uint shift = (pos & 3u) * 8u; uint mask = 0xffu << shift;
    uint old_value = out_words[word_i];
    for (;;) { uint next = (old_value & ~mask) | ((value & 0xffu) << shift); uint prior; InterlockedCompareExchange(out_words[word_i], old_value, next, prior); if (prior == old_value) return; old_value = prior; }
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x; if (i >= gLink.relocation_count) return;
    LinkRelocation row = link_relocation[i];
    uint target = INVALID;
    if (row.target_kind == 1u)
    {
        target = row.target_index;
    }
    else if (row.target_kind == 2u)
    {
        uint representative = lookup_identity_value(row.target_identity);
        if (representative == INVALID) { fail(4u, i); return; }
        target = link_symbol_definition[representative];
    }
    else if (row.target_kind == 3u)
    {
        target = row.target_index;
        int data_value = int(target) + asint(row.addend);
        if (data_value < 0) { fail(6u, i); return; }
        uint value = uint(data_value);
        uint body_start = 8u + 11u + WASM_HOST_TYPE_ENTRIES_LENGTH + gLink.type_len +
            WASM_HOST_IMPORT_SECTION_LENGTH + 11u + 5u * gLink.function_count +
            WASM_MEMORY_SECTION_LENGTH + WASM_GLOBAL_SECTION_LENGTH +
            WASM_EXPORT_SECTION_LENGTH + 11u;
        for (uint b = 0u; b < 5u; b += 1u)
            write_byte(body_start + row.body_offset + b,
                ((value >> (7u * b)) & 0x7fu) | (b < 4u ? 0x80u : 0u));
        return;
    }
    else { fail(7u, i); return; }
    if (target == INVALID) { fail(5u, i); return; }
    int adjusted = int(target) + int(WASM_HOST_IMPORT_COUNT) + asint(row.addend); if (adjusted < 0) { fail(6u, i); return; }
    uint body_start = 8u + 11u + WASM_HOST_TYPE_ENTRIES_LENGTH + gLink.type_len +
        WASM_HOST_IMPORT_SECTION_LENGTH + 11u + 5u * gLink.function_count +
        WASM_MEMORY_SECTION_LENGTH + WASM_GLOBAL_SECTION_LENGTH +
        WASM_EXPORT_SECTION_LENGTH + 11u;
    uint value = uint(adjusted); for (uint b = 0u; b < 5u; b += 1u) write_byte(body_start + row.body_offset + b, ((value >> (7u * b)) & 0x7fu) | (b < 4u ? 0x80u : 0u));
}
