import codegen.lowering_ir;

static const uint SCHEDULE_INVALID = 0xffffffffu;
static const uint SCHEDULE_EXPRESSION_TIE_MAX = 0x7fffffffu;
static const uint SCHEDULE_DENSE_TIE_FLAG = 0x80000000u;

uint target_schedule_field_width(uint packed_bits, uint field)
{
    return clamp((packed_bits >> (field * 6u)) & 0x3fu, 1u, 32u);
}

uint target_schedule_field(SemanticLirSchedule key, uint field)
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
    SemanticLirSchedule key,
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

void target_schedule_or_word(inout TargetScheduleKey key, uint word, uint value)
{
    if (word == 0u) key.word0 |= value;
    else if (word == 1u) key.word1 |= value;
    else key.word2 |= value;
}

TargetScheduleKey target_schedule_pack(
    SemanticLirSchedule schedule,
    uint packed_bits)
{
    TargetScheduleKey key;
    key.word0 = 0u;
    key.word1 = 0u;
    key.word2 = 0u;
    uint destination_bit = 0u;
    for (uint field = 0u; field < 4u; field += 1u)
    {
        uint width = target_schedule_field_width(packed_bits, field);
        uint value = target_schedule_encoded_field(
            schedule, field, width, packed_bits);
        uint word = destination_bit / 32u;
        uint shift = destination_bit % 32u;
        target_schedule_or_word(key, word, value << shift);
        if (shift != 0u && width > 32u - shift)
            target_schedule_or_word(key, word + 1u, value >> (32u - shift));
        destination_bit += width;
    }
    return key;
}

uint target_schedule_word(TargetScheduleKey key, uint word)
{
    return word == 0u ? key.word0 : word == 1u ? key.word1 : key.word2;
}

uint target_schedule_radix_key(TargetScheduleKey key, uint key_step, uint packed_bits)
{
    uint source_bit = key_step * 8u;
    uint word = source_bit / 32u;
    uint shift = source_bit % 32u;
    uint result = target_schedule_word(key, word) >> shift;
    if (shift > 24u && word < 2u)
        result |= target_schedule_word(key, word + 1u) << (32u - shift);
    return result & 0xffu;
}
