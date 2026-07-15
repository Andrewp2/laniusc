// Fully parallel scatter of flattened object section bytes into linked ELF sections.

import atomics;
import byte_packing;
import gpu_index;

struct Params
{
    uint object_count;
    uint text_input_len;
    uint rodata_input_len;
    uint reserved;
    uint text_input_base;
    uint rodata_input_base;
    uint output_page_base;
    uint output_page_len;
};

ConstantBuffer<Params> gCopy;

ByteAddressBuffer link_text_input;
ByteAddressBuffer link_rodata_input;
StructuredBuffer<uint> x86_elf_layout;
StructuredBuffer<uint> layout_status;

RWStructuredBuffer<uint> out_words;

static const uint X86_LAYOUT_OK = 1u;

void scatter_byte(uint file_pos, uint value)
{
    if (file_pos < gCopy.output_page_base ||
        file_pos - gCopy.output_page_base >= gCopy.output_page_len)
        return;
    file_pos -= gCopy.output_page_base;
    atomic_u32_or(
        out_words,
        file_pos >> 2u,
        (value & 0xffu) << ((file_pos & 3u) * 8u));
}

void copy_input_byte(uint local_pos, bool rodata)
{
    uint input_base = rodata ? gCopy.rodata_input_base : gCopy.text_input_base;
    uint pos = input_base + local_pos;
    uint section_file_start = rodata ? x86_elf_layout[6u] : x86_elf_layout[0u];
    uint byte_value = rodata
        ? byte_address_load_u8(link_rodata_input, local_pos)
        : byte_address_load_u8(link_text_input, local_pos);
    scatter_byte(section_file_start + pos, byte_value);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (layout_status[0u] != X86_LAYOUT_OK || layout_status[1u] != 0u)
        return;

    uint local_pos = linear_dispatch_thread_id_2d(tid, 16776960u);
    if (local_pos < gCopy.text_input_len)
        copy_input_byte(local_pos, false);
    if (local_pos < gCopy.rodata_input_len)
        copy_input_byte(local_pos, true);
}
