import byte_packing;
struct LinkParams { uint function_count; uint type_len; uint body_len; uint entry_function; uint symbol_count; uint relocation_count; uint hash_capacity; uint output_len; };
ConstantBuffer<LinkParams> gLink;
ByteAddressBuffer link_type_bytes;
ByteAddressBuffer link_body_bytes;
RWStructuredBuffer<uint> out_words;

uint leb5(uint value, uint i) { uint b = (value >> (i * 7u)) & 0x7fu; return i < 4u ? b | 0x80u : b; }
uint byte_at(uint pos)
{
    if (pos >= gLink.output_len) return 0u;
    if (pos == 0u) return 0u; if (pos == 1u) return 0x61u; if (pos == 2u) return 0x73u; if (pos == 3u) return 0x6du;
    if (pos == 4u) return 1u; if (pos >= 5u && pos < 8u) return 0u;
    uint type_start = 8u; uint type_payload = 5u + gLink.type_len; uint func_start = type_start + 6u + type_payload;
    uint func_payload = 5u + 5u * gLink.function_count; uint export_start = func_start + 6u + func_payload;
    uint code_start = export_start + 22u; uint code_payload = 5u + gLink.body_len; uint body_start = code_start + 11u;
    if (pos < func_start) { uint r = pos - type_start; if (r == 0u) return 1u; if (r < 6u) return leb5(type_payload, r - 1u); if (r < 11u) return leb5(gLink.function_count, r - 6u); return byte_address_load_u8(link_type_bytes, r - 11u); }
    if (pos < export_start) { uint r = pos - func_start; if (r == 0u) return 3u; if (r < 6u) return leb5(func_payload, r - 1u); if (r < 11u) return leb5(gLink.function_count, r - 6u); r -= 11u; return leb5(r / 5u, r % 5u); }
    if (pos < code_start) { uint r = pos - export_start; if (r == 0u) return 7u; if (r < 6u) return leb5(16u, r - 1u); if (r < 11u) return leb5(1u, r - 6u); if (r == 11u) return 4u; if (r == 12u) return 109u; if (r == 13u) return 97u; if (r == 14u) return 105u; if (r == 15u) return 110u; if (r == 16u) return 0u; return leb5(gLink.entry_function, r - 17u); }
    if (pos < body_start) { uint r = pos - code_start; if (r == 0u) return 10u; if (r < 6u) return leb5(code_payload, r - 1u); return leb5(gLink.function_count, r - 6u); }
    return byte_address_load_u8(link_body_bytes, pos - body_start);
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint word = tid.x; uint pos = word * 4u; if (pos >= gLink.output_len) return;
    out_words[word] = pack_u8x4(byte_at(pos), byte_at(pos + 1u), byte_at(pos + 2u), byte_at(pos + 3u));
}
