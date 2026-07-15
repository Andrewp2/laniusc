// Apply section-relative and symbol-targeted x86 relocations in parallel.

import atomics;
import byte_packing;
import gpu_index;

struct Params
{
    uint object_count;
    uint relocation_count;
    uint reserved_symbol_count;
    uint relocation_index_base;
    uint output_page_base;
    uint output_page_len;
    uint reserved_2;
    uint reserved_3;
};

ConstantBuffer<Params> gReloc;

// relocation a: (object, kind, site section, site offset)
// relocation b: (target kind, global target index, target offset, addend low)
// relocation c: (addend high, 0, 0, 0)
StructuredBuffer<uint4> link_relocation_a;
StructuredBuffer<uint4> link_relocation_b;
StructuredBuffer<uint4> link_relocation_c;
StructuredBuffer<uint> x86_elf_layout;

RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> link_relocation_status;

static const uint TARGET_SECTION_OFFSET = 1u;
static const uint TARGET_SYMBOL = 2u;
static const uint RELOC_REL32 = 1u;
static const uint RELOC_CALL_REL32 = 2u;
static const uint RELOC_ABS32 = 3u;
static const uint X86_LINK_RELOCATION_ERROR = 2u;
static const uint ELF_BASE_VADDR = 0x400000u;

void publish_error(uint subtype, uint relocation_i)
{
    uint global_relocation_i = gReloc.relocation_index_base + relocation_i;
    uint detail = (subtype << 28u) | min(global_relocation_i, 0x0fffffffu);
    atomic_u32_min(link_relocation_status, 2u, detail);
    link_relocation_status[0u] = 0u;
    link_relocation_status[1u] = X86_LINK_RELOCATION_ERROR;
}

void patch_byte(uint file_pos, uint value)
{
    if (file_pos < gReloc.output_page_base ||
        file_pos - gReloc.output_page_base >= gReloc.output_page_len)
        return;
    file_pos -= gReloc.output_page_base;
    uint word_i = file_pos >> 2u;
    uint shift = (file_pos & 3u) * 8u;
    uint mask = 0xffu << shift;
    atomic_u32_and(out_words, word_i, ~mask);
    atomic_u32_or(out_words, word_i, (value & 0xffu) << shift);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint relocation_i = linear_dispatch_thread_id_2d(tid, 16776960u);
    if (relocation_i >= gReloc.relocation_count)
        return;
    uint4 a = link_relocation_a[relocation_i];
    uint4 b = link_relocation_b[relocation_i];
    uint4 c = link_relocation_c[relocation_i];
    // The bounded layout scan has already materialized absolute file offsets
    // into each relocation batch.
    uint site_file = a.x;
    if (site_file + 4u < site_file ||
        site_file + 4u > x86_elf_layout[2u])
    {
        publish_error(2u, relocation_i);
        return;
    }

    if (b.y != TARGET_SECTION_OFFSET && b.y != TARGET_SYMBOL)
    {
        publish_error(7u, relocation_i);
        return;
    }
    uint target_file = b.x;

    // Object validation guarantees the signed addend is represented by the
    // complete low/high pair. x86 rel32 consumes its two's-complement low word;
    // the small code model keeps linked section distances within 32 bits.
    uint value = 0u;
    if (a.y == RELOC_REL32 || a.y == RELOC_CALL_REL32)
        value = target_file + b.w - site_file;
    else if (a.y == RELOC_ABS32)
        value = ELF_BASE_VADDR + target_file + b.w;
    else
    {
        publish_error(8u, relocation_i);
        return;
    }

    // Reject addends that are not sign-extended i32 values. This keeps the
    // current 32-bit relocation model exact while retaining i64 in the object
    // container for future large-model relocation kinds.
    uint expected_high = (b.w & 0x80000000u) == 0u ? 0u : 0xffffffffu;
    if (c.x != expected_high)
    {
        publish_error(9u, relocation_i);
        return;
    }

    patch_byte(site_file + 0u, u32_le_byte(value, 0u));
    patch_byte(site_file + 1u, u32_le_byte(value, 1u));
    patch_byte(site_file + 2u, u32_le_byte(value, 2u));
    patch_byte(site_file + 3u, u32_le_byte(value, 3u));
}
