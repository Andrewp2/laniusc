// Compact string-literal lookup shared by x86 instruction generation passes.

struct X86HirPayload { uint a; uint b; uint c; uint d; };
struct X86HirString { uint node; uint data_offset; uint decoded_len; uint file_id; };

StructuredBuffer<uint> x86_raw_to_compact_hir;
StructuredBuffer<uint> x86_compact_hir_count;
StructuredBuffer<X86HirPayload> x86_compact_hir_payload;
StructuredBuffer<uint> x86_compact_string_count;
StructuredBuffer<X86HirString> x86_compact_strings;

static const uint X86_STRING_INVALID = 0xffffffffu;

uint x86_string_decoded_len_for_raw(uint raw, uint raw_capacity)
{
    if (raw == X86_STRING_INVALID || raw >= raw_capacity)
        return X86_STRING_INVALID;
    uint dense_count = min(x86_compact_hir_count[0u], raw_capacity);
    uint dense = x86_raw_to_compact_hir[raw];
    if (dense == X86_STRING_INVALID || dense >= dense_count)
        return X86_STRING_INVALID;
    uint row = x86_compact_hir_payload[dense].b;
    uint string_count = min(x86_compact_string_count[0u], raw_capacity);
    if (row == X86_STRING_INVALID || row >= string_count)
        return X86_STRING_INVALID;
    X86HirString string_row = x86_compact_strings[row];
    return string_row.node == dense ? string_row.decoded_len : X86_STRING_INVALID;
}
