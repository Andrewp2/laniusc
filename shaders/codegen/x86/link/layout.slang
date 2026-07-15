// Final object section bases and ELF layout for an x86 multi-object link.

import gpu_index;
import prefix_scan;

struct Params
{
    uint object_count;
    uint object_block_count;
    uint entry_object_index;
    uint out_capacity;
    uint text_base;
    uint rodata_base;
    uint prior_entry_text_offset;
    uint finalize;
};

ConstantBuffer<Params> gLink;

StructuredBuffer<uint4> link_object_sections;
StructuredBuffer<uint> link_object_entry_offset;
StructuredBuffer<uint2> link_section_local_prefix;
StructuredBuffer<uint2> link_section_block_prefix;

RWStructuredBuffer<uint2> link_object_section_base;
RWStructuredBuffer<uint> x86_elf_layout;
RWStructuredBuffer<uint> layout_status;

static const uint ELF_BASE_VADDR = 0x400000u;
static const uint ELF_TEXT_OFFSET = 0x78u;
static const uint ELF_ALIGN = 0x1000u;
static const uint X86_LAYOUT_OK = 1u;

uint2 object_prefix(uint object_i)
{
    return global_exclusive_prefix_u32x2(
        object_i,
        256u,
        link_section_local_prefix,
        link_section_block_prefix);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint object_i = linear_dispatch_thread_id_2d(tid, 16776960u);
    if (object_i >= gLink.object_count)
        return;

    uint2 local_prefix = object_prefix(object_i);
    uint2 prefix = local_prefix + uint2(gLink.text_base, gLink.rodata_base);
    link_object_section_base[object_i] = prefix;

    if (object_i != 0u)
        return;

    uint last = gLink.object_count - 1u;
    uint2 local_totals = object_prefix(last) + link_object_sections[last].yw;
    uint2 totals = local_totals + uint2(gLink.text_base, gLink.rodata_base);
    uint rodata_offset = ELF_TEXT_OFFSET + totals.x;
    uint file_len = rodata_offset + totals.y;
    uint entry_offset = gLink.prior_entry_text_offset;
    bool entry_ok = entry_offset != 0xffffffffu;
    if (gLink.entry_object_index < gLink.object_count)
    {
        uint entry_base = gLink.text_base + object_prefix(gLink.entry_object_index).x;
        entry_offset = entry_base + link_object_entry_offset[gLink.entry_object_index];
        entry_ok = entry_base >= gLink.text_base && entry_offset >= entry_base;
    }
    bool totals_ok = totals.x >= gLink.text_base && totals.y >= gLink.rodata_base;
    bool ok = gLink.finalize != 0u &&
              totals_ok &&
              entry_ok &&
              file_len >= rodata_offset &&
              rodata_offset >= ELF_TEXT_OFFSET &&
              file_len <= gLink.out_capacity;

    x86_elf_layout[0u] = ELF_TEXT_OFFSET;
    x86_elf_layout[1u] = totals.x;
    x86_elf_layout[2u] = ok ? file_len : 0u;
    x86_elf_layout[3u] = ELF_BASE_VADDR + ELF_TEXT_OFFSET + entry_offset;
    x86_elf_layout[4u] = ELF_BASE_VADDR;
    x86_elf_layout[5u] = ELF_ALIGN;
    x86_elf_layout[6u] = rodata_offset;
    x86_elf_layout[7u] = totals.y;

    layout_status[0u] = ok ? X86_LAYOUT_OK : 0u;
    layout_status[1u] = ok ? 0u : 7u;
    layout_status[2u] = ok ? 0xffffffffu : file_len;
    layout_status[3u] = ok ? file_len : 0u;
}
