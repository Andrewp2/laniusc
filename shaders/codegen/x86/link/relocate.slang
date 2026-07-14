// Apply section-relative and symbol-targeted x86 relocations in parallel.

import atomics;
import byte_packing;
import gpu_index;

struct Params
{
    uint object_count;
    uint relocation_count;
    uint symbol_count;
    uint reserved;
};

ConstantBuffer<Params> gReloc;

// relocation a: (object, kind, site section, site offset)
// relocation b: (target kind, global target index, target offset, addend low)
// relocation c: (addend high, 0, 0, 0)
StructuredBuffer<uint4> link_relocation_a;
StructuredBuffer<uint4> link_relocation_b;
StructuredBuffer<uint4> link_relocation_c;
StructuredBuffer<uint2> link_object_section_base;
StructuredBuffer<uint4> link_symbol_identity_section;
// (object, offset, size, flags)
StructuredBuffer<uint4> link_symbol_location;
StructuredBuffer<uint> link_symbol_definition;
StructuredBuffer<uint> link_symbol_status;
StructuredBuffer<uint> x86_elf_layout;

RWStructuredBuffer<uint> out_words;
RWStructuredBuffer<uint> link_relocation_status;

static const uint INVALID = 0xffffffffu;
static const uint SECTION_TEXT = 1u;
static const uint SECTION_RODATA = 2u;
static const uint TARGET_SECTION_OFFSET = 1u;
static const uint TARGET_SYMBOL = 2u;
static const uint RELOC_REL32 = 1u;
static const uint RELOC_CALL_REL32 = 2u;
static const uint RELOC_ABS32 = 3u;
static const uint X86_LINK_RELOCATION_ERROR = 2u;
static const uint ELF_BASE_VADDR = 0x400000u;

bool section_file_offset(
    uint object_i,
    uint section,
    uint section_offset,
    out uint file_offset)
{
    file_offset = 0u;
    if (object_i >= gReloc.object_count)
        return false;
    uint2 base = link_object_section_base[object_i];
    if (section == SECTION_TEXT)
    {
        file_offset = x86_elf_layout[0u] + base.x + section_offset;
        return file_offset >= x86_elf_layout[0u];
    }
    if (section == SECTION_RODATA)
    {
        file_offset = x86_elf_layout[6u] + base.y + section_offset;
        return file_offset >= x86_elf_layout[6u];
    }
    return false;
}

void publish_error(uint subtype, uint relocation_i)
{
    uint detail = (subtype << 28u) | min(relocation_i, 0x0fffffffu);
    atomic_u32_min(link_relocation_status, 2u, detail);
    link_relocation_status[0u] = 0u;
    link_relocation_status[1u] = X86_LINK_RELOCATION_ERROR;
}

void patch_byte(uint file_pos, uint value)
{
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
    if (link_symbol_status[0u] == 0u || link_symbol_status[1u] != 0u)
    {
        publish_error(1u, relocation_i);
        return;
    }

    uint4 a = link_relocation_a[relocation_i];
    uint4 b = link_relocation_b[relocation_i];
    uint4 c = link_relocation_c[relocation_i];
    uint site_file = 0u;
    if (!section_file_offset(a.x, a.z, a.w, site_file) ||
        site_file + 4u < site_file ||
        site_file + 4u > x86_elf_layout[2u])
    {
        publish_error(2u, relocation_i);
        return;
    }

    uint target_file = 0u;
    if (b.x == TARGET_SECTION_OFFSET)
    {
        if (!section_file_offset(a.x, b.y, b.z, target_file))
        {
            publish_error(3u, relocation_i);
            return;
        }
    }
    else if (b.x == TARGET_SYMBOL)
    {
        if (b.y >= gReloc.symbol_count)
        {
            publish_error(4u, relocation_i);
            return;
        }
        uint definition = link_symbol_definition[b.y];
        if (definition == INVALID || definition >= gReloc.symbol_count)
        {
            publish_error(5u, relocation_i);
            return;
        }
        uint4 definition_location = link_symbol_location[definition];
        uint definition_section = link_symbol_identity_section[definition].w;
        if (!section_file_offset(
                definition_location.x,
                definition_section,
                definition_location.y,
                target_file))
        {
            publish_error(6u, relocation_i);
            return;
        }
    }
    else
    {
        publish_error(7u, relocation_i);
        return;
    }

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
