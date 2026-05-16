// Direct x86_64 relocation patching.
//
// Instruction encoding writes branch/call relocation fields as zero bytes. This
// pass consumes GPU-produced relocation records plus GPU-computed instruction
// offsets and patches relative displacements before ELF writing.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_inst_kind;
StructuredBuffer<uint> x86_inst_size;
StructuredBuffer<uint> x86_inst_byte_offset;
StructuredBuffer<uint> x86_text_len;
StructuredBuffer<uint> text_status;
StructuredBuffer<uint> encode_status;
StructuredBuffer<uint> x86_reloc_count;
StructuredBuffer<uint> x86_reloc_kind;
StructuredBuffer<uint> x86_reloc_site_inst;
StructuredBuffer<uint> x86_reloc_target_inst;

RWStructuredBuffer<uint> x86_text_words;
RWStructuredBuffer<uint> reloc_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_ENCODE_OK = 1u;
static const uint X86_RELOC_OK = 1u;
static const uint X86_ERR_RELOC = 8u;

static const uint X86_INST_JCC_FALSE_REL32 = 9u;
static const uint X86_INST_JMP_REL32 = 10u;
static const uint X86_INST_CALL_REL32 = 15u;
static const uint X86_RELOC_REL32 = 1u;
static const uint X86_RELOC_CALL_REL32 = 2u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint le32_byte(uint value, uint byte_i)
{
    return (value >> (byte_i * 8u)) & 0xffu;
}

uint rel32_to_inst(uint site_inst, uint target_inst)
{
    uint source_next = x86_inst_byte_offset[site_inst] + x86_inst_size[site_inst];
    uint target = x86_inst_byte_offset[target_inst];
    return target - source_next;
}

uint rel32_imm_offset(uint inst_kind)
{
    if (inst_kind == X86_INST_JCC_FALSE_REL32) return 2u;
    if (inst_kind == X86_INST_JMP_REL32) return 1u;
    if (inst_kind == X86_INST_CALL_REL32) return 1u;
    return 0xffffffffu;
}

bool reloc_kind_matches_inst(uint reloc_kind, uint inst_kind)
{
    if (reloc_kind == X86_RELOC_REL32)
        return inst_kind == X86_INST_JCC_FALSE_REL32 || inst_kind == X86_INST_JMP_REL32;
    if (reloc_kind == X86_RELOC_CALL_REL32)
        return inst_kind == X86_INST_CALL_REL32;
    return false;
}

void write_text_byte(uint pos, uint value)
{
    uint word_i = pos / 4u;
    uint byte_i = pos & 3u;
    uint shift = byte_i * 8u;
    uint mask = 0xffu << shift;
    uint old_word = x86_text_words[word_i];
    x86_text_words[word_i] = (old_word & ~mask) | ((value & 0xffu) << shift);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint reloc_i = linear_dispatch_id(tid);
    bool encode_ok = encode_status[0u] == X86_ENCODE_OK && encode_status[1u] == 0u;
    uint reloc_n = encode_ok ? x86_reloc_count[0u] : 0u;
    uint inst_count = encode_ok ? text_status[3u] : 0u;
    uint text_len = encode_ok ? x86_text_len[0u] : 0u;

    if (reloc_i == 0u)
    {
        reloc_status[0u] = encode_ok ? X86_RELOC_OK : 0u;
        reloc_status[1u] = encode_ok ? 0u : encode_status[1u];
        reloc_status[2u] = encode_ok ? 0xffffffffu : encode_status[2u];
        reloc_status[3u] = encode_ok ? text_len : 0u;
    }

    GroupMemoryBarrierWithGroupSync();

    if (!encode_ok || reloc_i >= reloc_n)
        return;

    uint kind = x86_reloc_kind[reloc_i];
    uint site_inst = x86_reloc_site_inst[reloc_i];
    uint target_inst = x86_reloc_target_inst[reloc_i];
    bool record_ok = site_inst < inst_count &&
                     target_inst < inst_count;
    uint site_kind = record_ok ? x86_inst_kind[site_inst] : 0u;
    record_ok = record_ok && reloc_kind_matches_inst(kind, site_kind);
    uint imm_offset = record_ok ? rel32_imm_offset(site_kind) : 0xffffffffu;
    record_ok = record_ok && imm_offset != 0xffffffffu &&
                x86_inst_byte_offset[site_inst] + imm_offset + 4u <= text_len;

    if (!record_ok)
    {
        reloc_status[0u] = 0u;
        reloc_status[1u] = X86_ERR_RELOC;
        uint old_detail = 0u;
        InterlockedMin(reloc_status[2u], reloc_i, old_detail);
        return;
    }

    uint rel = rel32_to_inst(site_inst, target_inst);
    uint imm_pos = x86_inst_byte_offset[site_inst] + imm_offset;
    write_text_byte(imm_pos + 0u, le32_byte(rel, 0u));
    write_text_byte(imm_pos + 1u, le32_byte(rel, 1u));
    write_text_byte(imm_pos + 2u, le32_byte(rel, 2u));
    write_text_byte(imm_pos + 3u, le32_byte(rel, 3u));
}
