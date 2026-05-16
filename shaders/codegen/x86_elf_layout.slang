// Direct x86_64 ELF layout.
//
// This pass turns encoded text length into GPU-visible ELF layout records. The
// writer consumes these records instead of hard-coding file length and entry
// layout decisions in the byte writer.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_text_len;
StructuredBuffer<uint> encode_status;

RWStructuredBuffer<uint> x86_elf_layout;
RWStructuredBuffer<uint> layout_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_ENCODE_OK = 1u;
static const uint X86_LAYOUT_OK = 1u;
static const uint X86_ERR_OUTPUT_TOO_SMALL = 4u;
static const uint X86_ERR_ELF_LAYOUT = 7u;

static const uint ELF_BASE_VADDR = 0x400000u;
static const uint ELF_TEXT_OFFSET = 0x78u;
static const uint ELF_ALIGN = 0x1000u;

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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint lane = linear_dispatch_id(tid);

    bool encode_ok = encode_status[0u] == X86_ENCODE_OK && encode_status[1u] == 0u &&
                     encode_status[3u] == x86_text_len[0u] && x86_text_len[0u] > 0u;
    uint file_len = ELF_TEXT_OFFSET + x86_text_len[0u];
    bool capacity_ok = file_len <= gParams.out_capacity;
    bool ok = encode_ok && capacity_ok;

    if (lane == LAYOUT_TEXT_OFFSET) x86_elf_layout[LAYOUT_TEXT_OFFSET] = ELF_TEXT_OFFSET;
    if (lane == LAYOUT_TEXT_LEN) x86_elf_layout[LAYOUT_TEXT_LEN] = encode_ok ? x86_text_len[0u] : 0u;
    if (lane == LAYOUT_FILE_LEN) x86_elf_layout[LAYOUT_FILE_LEN] = encode_ok ? file_len : 0u;
    if (lane == LAYOUT_ENTRY_VADDR) x86_elf_layout[LAYOUT_ENTRY_VADDR] = ELF_BASE_VADDR + ELF_TEXT_OFFSET;
    if (lane == LAYOUT_BASE_VADDR) x86_elf_layout[LAYOUT_BASE_VADDR] = ELF_BASE_VADDR;
    if (lane == LAYOUT_ALIGN) x86_elf_layout[LAYOUT_ALIGN] = ELF_ALIGN;

    if (lane == 0u)
    {
        layout_status[0u] = ok ? X86_LAYOUT_OK : 0u;
        layout_status[1u] = ok ? 0u : (!encode_ok ? encode_status[1u] : X86_ERR_OUTPUT_TOO_SMALL);
        layout_status[2u] = ok ? 0xffffffffu : (!encode_ok ? encode_status[2u] : gParams.out_capacity);
        layout_status[3u] = ok ? file_len : 0u;
        if (!ok && layout_status[1u] == 0u)
            layout_status[1u] = X86_ERR_ELF_LAYOUT;
    }
}
