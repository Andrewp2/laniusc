// Build indirect dispatch arguments for x86 output emission.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_text_len;
StructuredBuffer<uint> text_status;

RWStructuredBuffer<uint> active_text_word_dispatch_args;
RWStructuredBuffer<uint> active_elf_header_word_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint X86_TEXT_OK = 1u;
static const uint ELF_TEXT_OFFSET = 0x78u;

uint div_ceil_u32(uint value, uint divisor)
{
    return (value + divisor - 1u) / divisor;
}

void write_dispatch_args(RWStructuredBuffer<uint> args, uint active_records)
{
    uint groups = max(1u, div_ceil_u32(active_records, WG_SIZE));
    args[0u] = min(groups, MAX_GROUPS_X);
    args[1u] = max(1u, div_ceil_u32(groups, MAX_GROUPS_X));
    args[2u] = 1u;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x != 0u || tid.y != 0u || tid.z != 0u)
        return;

    bool text_ok = text_status[0u] == X86_TEXT_OK && text_status[1u] == 0u;
    uint text_words = text_ok ? div_ceil_u32(x86_text_len[0u], 4u) : 0u;
    uint header_words = div_ceil_u32(ELF_TEXT_OFFSET, 4u);
    write_dispatch_args(active_text_word_dispatch_args, text_words);
    write_dispatch_args(active_elf_header_word_dispatch_args, header_words);
}
