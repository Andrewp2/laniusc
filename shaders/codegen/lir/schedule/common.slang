import codegen.lowering_ir;

uint target_schedule_radix_key(TargetScheduleKey key, uint key_step)
{
    uint field_step = min(key_step / 4u, 3u);
    uint byte_step = key_step & 3u;
    // Least-significant field first for a stable lexicographic LSD sort.
    // Semantic lowering assigns one source-ordered region per expression
    // forest, then a reversed dependency depth inside that region.
    uint field = field_step == 0u ? key.execution_tie
        : field_step == 1u ? key.execution_rank
        : field_step == 2u ? key.execution_region
        : key.function_id;
    return (field >> (byte_step * 8u)) & 0xffu;
}
