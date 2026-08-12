import codegen.lowering_ir;

static const uint SCHEDULE_INVALID = 0xffffffffu;
static const uint SCHEDULE_EXPRESSION_TIE_MAX = 0x7fffffffu;
static const uint SCHEDULE_DENSE_TIE_FLAG = 0x80000000u;

uint target_schedule_field_width(uint packed_bits, uint field)
{
    return clamp((packed_bits >> (field * 6u)) & 0x3fu, 1u, 32u);
}

uint target_schedule_field(TargetScheduleKey key, uint field)
{
    return field == 0u ? key.execution_tie
        : field == 1u ? key.execution_rank
        : field == 2u ? key.execution_region
        : key.function_id;
}

uint target_schedule_field_mask(uint width)
{
    return width == 32u ? 0xffffffffu : (1u << width) - 1u;
}

uint target_schedule_encoded_field(
    TargetScheduleKey key,
    uint field,
    uint width,
    uint packed_bits)
{
    uint mask = target_schedule_field_mask(width);
    uint value = target_schedule_field(key, field);
    if (value == SCHEDULE_INVALID)
        return mask;

    // Expression rows encode reversed dependency depth as
    // 0x7fff_ffff-depth so they sort above ordinary local-row ties and below
    // the final-effect sentinel. Map that sparse high band into the top of the
    // capacity-sized tie field without changing its ordering.
    if (field == 0u && (packed_bits & SCHEDULE_DENSE_TIE_FLAG) != 0u &&
        value >= 0x40000000u && value <= SCHEDULE_EXPRESSION_TIE_MAX)
    {
        uint depth = SCHEDULE_EXPRESSION_TIE_MAX - value;
        return mask - 1u - min(depth, mask - 1u);
    }
    return value & mask;
}

uint target_schedule_radix_key(TargetScheduleKey key, uint key_step, uint packed_bits)
{
    uint source_bit = key_step * 8u;
    uint field = 0u;
    for (; field < 4u; field += 1u)
    {
        uint width = target_schedule_field_width(packed_bits, field);
        if (source_bit < width)
            break;
        source_bit -= width;
    }

    uint result = 0u;
    uint written = 0u;
    for (uint part = 0u; part < 4u && field < 4u && written < 8u; part += 1u)
    {
        uint width = target_schedule_field_width(packed_bits, field);
        uint take = min(width - source_bit, 8u - written);
        uint value = target_schedule_encoded_field(key, field, width, packed_bits);
        uint take_mask = (1u << take) - 1u;
        result |= ((value >> source_bit) & take_mask) << written;
        written += take;
        field += 1u;
        source_bit = 0u;
    }
    return result;
}
