import byte_packing;
import codegen.lir.wasm.host_abi;
import codegen.lir.wasm.module_sections;
struct LinkParams
{
    uint function_count;
    uint type_len;
    uint body_len;
    uint entry_function;
    uint symbol_count;
    uint relocation_count;
    uint hash_capacity;
    uint output_len;
    uint output_page_base;
    uint output_page_len;
    uint type_input_base;
    uint body_input_base;
    uint data_len;
    uint data_input_base;
};
ConstantBuffer<LinkParams> gLink;
ByteAddressBuffer link_type_bytes;
ByteAddressBuffer link_body_bytes;
ByteAddressBuffer link_data_bytes;
RWStructuredBuffer<uint> out_words;

uint leb5(uint value, uint i) { uint b = (value >> (i * 7u)) & 0x7fu; return i < 4u ? b | 0x80u : b; }
uint byte_at(uint pos)
{
    if (pos >= gLink.output_len || pos < gLink.output_page_base ||
        pos - gLink.output_page_base >= gLink.output_page_len) return 0u;
    if (pos == 0u) return 0u; if (pos == 1u) return 0x61u; if (pos == 2u) return 0x73u; if (pos == 3u) return 0x6du;
    if (pos == 4u) return 1u; if (pos >= 5u && pos < 8u) return 0u;
    uint type_start = 8u;
    uint object_type_start = type_start + 11u + WASM_HOST_TYPE_ENTRIES_LENGTH;
    uint import_start = object_type_start + gLink.type_len;
    uint func_start = import_start + WASM_HOST_IMPORT_SECTION_LENGTH;
    uint func_payload = 5u + 5u * gLink.function_count;
    uint memory_start = func_start + 6u + func_payload;
    uint global_start = memory_start + WASM_MEMORY_SECTION_LENGTH;
    uint export_start = global_start + WASM_GLOBAL_SECTION_LENGTH;
    uint code_start = export_start + WASM_EXPORT_SECTION_LENGTH;
    uint code_payload = 5u + gLink.body_len;
    uint body_start = code_start + 11u;
    uint data_start = body_start + gLink.body_len;
    if (pos < object_type_start)
    {
        uint r = pos - type_start;
        if (r == 0u) return 1u;
        if (r < 6u) return leb5(5u + WASM_HOST_TYPE_ENTRIES_LENGTH + gLink.type_len, r - 1u);
        if (r < 11u) return leb5(WASM_HOST_TYPE_COUNT + gLink.function_count, r - 6u);
        return wasm_host_type_entries_byte(r - 11u);
    }
    if (pos < import_start)
        return byte_address_load_u8(link_type_bytes, pos - object_type_start - gLink.type_input_base);
    if (pos < func_start) return wasm_host_import_section_byte(pos - import_start);
    if (pos < memory_start)
    {
        uint r = pos - func_start;
        if (r == 0u) return 3u;
        if (r < 6u) return leb5(func_payload, r - 1u);
        if (r < 11u) return leb5(gLink.function_count, r - 6u);
        r -= 11u;
        return leb5(WASM_HOST_TYPE_COUNT + r / 5u, r % 5u);
    }
    if (pos < global_start) return wasm_memory_section_byte(pos - memory_start, 16384u);
    uint bump_start = (gLink.data_len + 3u) & ~3u;
    if (pos < export_start) return wasm_global_section_byte(pos - global_start, bump_start);
    if (pos < code_start)
        return wasm_export_section_byte(pos - export_start,
            WASM_HOST_IMPORT_COUNT + gLink.entry_function);
    if (pos < body_start) { uint r = pos - code_start; if (r == 0u) return 10u; if (r < 6u) return leb5(code_payload, r - 1u); return leb5(gLink.function_count, r - 6u); }
    if (pos < data_start)
        return byte_address_load_u8(link_body_bytes, pos - body_start - gLink.body_input_base);
    uint data_section_len = gLink.data_len == 0u ? 0u : 24u + gLink.data_len;
    if (gLink.data_len == 0u || pos >= data_start + data_section_len) return 0u;
    uint rel = pos - data_start;
    if (rel == 0u) return 11u;
    if (rel <= 5u) return leb5(18u + gLink.data_len, rel - 1u);
    if (rel <= 10u) return leb5(1u, rel - 6u);
    if (rel == 11u) return 0u;
    if (rel == 12u) return 0x41u;
    if (rel <= 17u) return leb5(0u, rel - 13u);
    if (rel == 18u) return 0x0bu;
    if (rel <= 23u) return leb5(gLink.data_len, rel - 19u);
    return byte_address_load_u8(link_data_bytes, rel - 24u - gLink.data_input_base);
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint word = tid.x; uint local_pos = word * 4u; if (local_pos >= gLink.output_page_len) return;
    uint pos = gLink.output_page_base + local_pos;
    out_words[word] = pack_u8x4(byte_at(pos), byte_at(pos + 1u), byte_at(pos + 2u), byte_at(pos + 3u));
}
