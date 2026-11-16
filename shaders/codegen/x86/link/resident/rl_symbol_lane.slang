// Maps a symbol capacity lane to its object and local symbol.

import codegen.x86.link.resident.rl_common;

// Object whose symbol capacity range holds `lane`, or INVALID.
public uint symbol_lane_object(uint lane)
{
    if (lane >= gRL.symbol_cap_total)
        return INVALID;
    uint low = 0u;
    uint high = gRL.object_count;
    while (high - low > 1u)
    {
        uint middle = low + (high - low) / 2u;
        if (slot_word(middle, 10u) <= lane)
            low = middle;
        else
            high = middle;
    }
    return low;
}

// For a valid lane: whether it is a definition, and its row index (undefined
// local index or definition index). False for an unused capacity lane.
public bool symbol_lane_row(uint object, uint lane, out bool definition, out uint index)
{
    uint local = lane - slot_word(object, 10u);
    uint undef_cap = slot_word(object, 5u);
    definition = local >= undef_cap;
    index = definition ? local - undef_cap : local;
    return definition ? index < object_word(object, OB_DEF_COUNT)
                      : index < object_word(object, OB_UNDEF_COUNT);
}

public uint decimal_digits(uint value)
{
    uint digits = 1u;
    while (value >= 10u)
    {
        value /= 10u;
        digits += 1u;
    }
    return digits;
}
