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
};

ConstantBuffer<Params> gCopy;

// (text input start, text length, rodata input start, rodata length)
StructuredBuffer<uint4> link_object_sections;
StructuredBuffer<uint2> link_object_section_base;
ByteAddressBuffer link_text_input;
ByteAddressBuffer link_rodata_input;
StructuredBuffer<uint> x86_elf_layout;
StructuredBuffer<uint> layout_status;

RWStructuredBuffer<uint> out_words;

static const uint X86_LAYOUT_OK = 1u;

uint section_end(uint object_i, bool rodata)
{
    uint4 record = link_object_sections[object_i];
    return rodata ? record.z + record.w : record.x + record.y;
}

uint object_for_input_byte(uint pos, bool rodata)
{
    uint lo = 0u;
    uint hi = gCopy.object_count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (section_end(mid, rodata) <= pos)
            lo = mid + 1u;
        else
            hi = mid;
    }
    return lo;
}

void scatter_byte(uint file_pos, uint value)
{
    atomic_u32_or(
        out_words,
        file_pos >> 2u,
        (value & 0xffu) << ((file_pos & 3u) * 8u));
}

void copy_input_byte(uint pos, bool rodata)
{
    uint object_i = object_for_input_byte(pos, rodata);
    if (object_i >= gCopy.object_count)
        return;

    uint4 record = link_object_sections[object_i];
    uint input_start = rodata ? record.z : record.x;
    uint input_len = rodata ? record.w : record.y;
    if (pos < input_start || pos - input_start >= input_len)
        return;

    uint2 output_base = link_object_section_base[object_i];
    uint section_file_start = rodata ? x86_elf_layout[6u] : x86_elf_layout[0u];
    uint object_output_start = rodata ? output_base.y : output_base.x;
    uint byte_value = rodata
        ? byte_address_load_u8(link_rodata_input, pos)
        : byte_address_load_u8(link_text_input, pos);
    scatter_byte(section_file_start + object_output_start + pos - input_start, byte_value);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (layout_status[0u] != X86_LAYOUT_OK || layout_status[1u] != 0u)
        return;

    uint pos = linear_dispatch_thread_id_2d(tid, 16776960u);
    if (pos < gCopy.text_input_len)
        copy_input_byte(pos, false);
    if (pos < gCopy.rodata_input_len)
        copy_input_byte(pos, true);
}
