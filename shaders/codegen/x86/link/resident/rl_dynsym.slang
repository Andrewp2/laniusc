// One lane per symbol capacity row: the dynamic writer's row of each defined
// Lanius symbol, in object order: (file offset, size, section, identity, 0, 0).

import codegen.x86.link.resident.rl_common;
import codegen.x86.link.resident.rl_symbol_lane;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint lane = rl_lane(tid);
    uint object = symbol_lane_object(lane);
    if (object == INVALID)
        return;
    bool definition;
    uint index;
    if (!symbol_lane_row(object, lane, definition, index) || !definition)
        return;
    uint base = lane * SYMBOL_WORDS;
    uint section = rl_symbols[base + 4u];
    uint section_base = section == 1u
        ? TEXT_OFFSET + object_word(object, OB_TEXT_OUT)
        : TEXT_OFFSET + gRL.text_len_total + object_word(object, OB_RODATA_OUT);
    uint row = gRL.dyn_symbol_rows + (object_word(object, OB_DEF_PREFIX) + index) * 8u;
    rl_dyn_words[row] = section_base + rl_symbols[base + 5u];
    rl_dyn_words[row + 1u] = rl_symbols[base + 6u];
    rl_dyn_words[row + 2u] = section;
    rl_dyn_words[row + 3u] = rl_symbols[base + 1u];
    rl_dyn_words[row + 4u] = rl_symbols[base + 2u];
    rl_dyn_words[row + 5u] = rl_symbols[base + 3u];
    rl_dyn_words[row + 6u] = 0u;
    rl_dyn_words[row + 7u] = 0u;
}
