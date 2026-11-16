// One lane per output word from the start of .text to the end of .rodata:
// gathers the copied text of each object, zero import text, and rodata.
// The dynamic writer and the relocations patch these words afterwards.

import codegen.x86.link.resident.rl_common;
import byte_packing;

uint section_byte(uint position, uint lanius_text, uint text_total, uint rodata_total)
{
    if (position < TEXT_OFFSET)
        return 0u;
    uint p = position - TEXT_OFFSET;
    if (p < lanius_text)
    {
        for (uint k = 0u; k < gRL.object_count; k += 1u)
        {
            uint start = object_word(k, OB_TEXT_OUT);
            uint len = object_word(k, OB_COPY_END) - object_word(k, OB_COPY_START);
            if (p >= start && p - start < len)
                return object_text_byte(k, object_word(k, OB_COPY_START) + (p - start));
        }
        return 0u;
    }
    if (p < text_total)
        return 0u;
    p -= text_total;
    if (p < rodata_total)
    {
        for (uint k = 0u; k < gRL.object_count; k += 1u)
        {
            uint start = object_word(k, OB_RODATA_OUT);
            if (p >= start && p - start < object_word(k, OB_RODATA_LEN))
                return object_rodata_byte(k, p - start);
        }
    }
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint word = gRL.output_word_begin + rl_lane(tid);
    if (word >= gRL.output_word_end)
        return;
    uint lanius_text = rl_status[ST_TEXT_LEN];
    uint rodata_total = rl_status[ST_RODATA_LEN];
    uint position = word * 4u;
    rl_out[word] = pack_u8x4(
        section_byte(position, lanius_text, gRL.text_len_total, rodata_total),
        section_byte(position + 1u, lanius_text, gRL.text_len_total, rodata_total),
        section_byte(position + 2u, lanius_text, gRL.text_len_total, rodata_total),
        section_byte(position + 3u, lanius_text, gRL.text_len_total, rodata_total));
}
