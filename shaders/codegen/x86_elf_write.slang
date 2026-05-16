// Direct x86_64 ELF writer for the first native backend slice.
//
// This pass consumes encoded `.text` words and writes the final packed ELF bytes
// directly into the output buffer.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_text_words;
StructuredBuffer<uint> x86_elf_layout;
StructuredBuffer<uint> layout_status;

RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_OK_PACKED = 1u;
static const uint X86_LAYOUT_OK = 1u;

static const uint LAYOUT_TEXT_OFFSET = 0u;
static const uint LAYOUT_TEXT_LEN = 1u;
static const uint LAYOUT_FILE_LEN = 2u;
static const uint LAYOUT_ENTRY_VADDR = 3u;
static const uint LAYOUT_BASE_VADDR = 4u;
static const uint LAYOUT_ALIGN = 5u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint le32_byte(uint value, uint byte_i)
{
    return (value >> (byte_i * 8u)) & 0xffu;
}

uint le64_small_byte(uint value, uint byte_i)
{
    return byte_i < 4u ? le32_byte(value, byte_i) : 0u;
}

uint elf_header_byte(uint pos)
{
    if (pos == 0u) return 0x7fu;
    if (pos == 1u) return 0x45u;
    if (pos == 2u) return 0x4cu;
    if (pos == 3u) return 0x46u;
    if (pos == 4u) return 2u;
    if (pos == 5u) return 1u;
    if (pos == 6u) return 1u;

    if (pos == 16u) return 2u;
    if (pos == 18u) return 0x3eu;
    if (pos == 20u) return 1u;

    if (pos >= 24u && pos < 32u)
    {
        return le64_small_byte(x86_elf_layout[LAYOUT_ENTRY_VADDR], pos - 24u);
    }
    if (pos == 32u) return 64u;
    if (pos == 52u) return 64u;
    if (pos == 54u) return 56u;
    if (pos == 56u) return 1u;
    return 0u;
}

uint program_header_byte(uint pos, uint file_len)
{
    uint p = pos - 64u;
    if (p == 0u) return 1u;
    if (p == 4u) return 5u;

    if (p >= 16u && p < 24u)
    {
        return le64_small_byte(x86_elf_layout[LAYOUT_BASE_VADDR], p - 16u);
    }
    if (p >= 24u && p < 32u)
    {
        return le64_small_byte(x86_elf_layout[LAYOUT_BASE_VADDR], p - 24u);
    }
    if (p >= 32u && p < 40u)
    {
        return le64_small_byte(file_len, p - 32u);
    }
    if (p >= 40u && p < 48u)
    {
        return le64_small_byte(file_len, p - 40u);
    }
    if (p >= 48u && p < 56u)
        return le64_small_byte(x86_elf_layout[LAYOUT_ALIGN], p - 48u);
    return 0u;
}

uint text_byte(uint pos)
{
    uint p = pos - x86_elf_layout[LAYOUT_TEXT_OFFSET];
    uint word = x86_text_words[p / 4u];
    return (word >> ((p % 4u) * 8u)) & 0xffu;
}

uint file_byte(uint pos, uint file_len)
{
    if (pos < 64u)
        return elf_header_byte(pos);
    if (pos < x86_elf_layout[LAYOUT_TEXT_OFFSET])
        return program_header_byte(pos, file_len);
    if (pos < file_len)
        return text_byte(pos);
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    bool layout_ok = layout_status[0u] == X86_LAYOUT_OK;
    uint error_code = layout_ok ? 0u : layout_status[1u];
    uint error_detail = layout_ok ? 0xffffffffu : layout_status[2u];

    uint text_offset = x86_elf_layout[LAYOUT_TEXT_OFFSET];
    uint text_len = x86_elf_layout[LAYOUT_TEXT_LEN];
    uint file_len = x86_elf_layout[LAYOUT_FILE_LEN];
    bool ok = layout_ok && layout_status[3u] == file_len && file_len == text_offset + text_len &&
              text_len > 0u && file_len <= gParams.out_capacity;

    if (tid.x == 0u && tid.y == 0u)
    {
        status[0u] = ok ? file_len : 0u;
        status[1u] = ok ? X86_OK_PACKED : 0u;
        status[2u] = ok ? 0u : error_code;
        status[3u] = ok ? 0xffffffffu : error_detail;
    }

    if (!ok)
        return;

    uint word_i = linear_dispatch_id(tid);
    uint word_count = (file_len + 3u) / 4u;
    if (word_i >= word_count)
        return;

    uint pos = word_i * 4u;
    uint b0 = file_byte(pos + 0u, file_len);
    uint b1 = file_byte(pos + 1u, file_len);
    uint b2 = file_byte(pos + 2u, file_len);
    uint b3 = file_byte(pos + 3u, file_len);
    out_words[word_i] = b0 | (b1 << 8u) | (b2 << 16u) | (b3 << 24u);
}
