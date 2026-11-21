// One lane per output word. Copy the interval that overlaps each object
// section, including words that straddle sections. The import text starts
// clear for the dynamic writer, and relocations patch the copied words.

import codegen.x86.link.resident_linking.resident_link_layout;

uint section_fragment(StructuredBuffer<uint> source, uint source_start,
                      uint section_start, uint section_end, uint position)
{
    uint first = max(section_start, position);
    uint end = min(section_end, position + 4u);
    if (first >= end) return 0u;
    uint count = end - first;
    uint offset = source_start + first - section_start;
    uint shift = (offset & 3u) * 8u;
    uint packed = source[offset >> 2u] >> shift;
    if ((offset & 3u) + count > 4u)
        packed |= source[(offset >> 2u) + 1u] << (32u - shift);
    return (packed & (0xffffffffu >> ((4u - count) * 8u))) <<
        ((first - position) * 8u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint word = gRL.output_word_begin + rl_lane(tid);
    if (word >= gRL.output_word_end) return;
    uint position = word * 4u;
    uint rodata_start = TEXT_OFFSET + gRL.text_len_total;
    uint packed = 0u;
    if (position + 4u > TEXT_OFFSET && position < TEXT_OFFSET + rl_status[ST_TEXT_LEN])
    {
        for (uint object = 0u; object < gRL.object_count; object += 1u)
        {
            uint start = TEXT_OFFSET + object_word(object, OB_TEXT_OUT);
            if (start >= position + 4u) break;
            uint copy_start = object_word(object, OB_COPY_START);
            uint end = start + object_word(object, OB_COPY_END) - copy_start;
            packed |= section_fragment(st_text, slot_word(object, 8u) + copy_start,
                start, end, position);
            if (end >= position + 4u) break;
        }
    }
    if (position + 4u > rodata_start && position < rodata_start + rl_status[ST_RODATA_LEN])
    {
        for (uint object = 0u; object < gRL.object_count; object += 1u)
        {
            uint start = rodata_start + object_word(object, OB_RODATA_OUT);
            if (start >= position + 4u) break;
            uint end = start + object_word(object, OB_RODATA_LEN);
            packed |= section_fragment(st_rodata, slot_word(object, 9u),
                start, end, position);
            if (end >= position + 4u) break;
        }
    }
    rl_out[word] = packed;
}
