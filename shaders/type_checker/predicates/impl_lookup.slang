// Compact exact index for concrete trait implementations. Every consumer
// verifies all five fields while traversing the selected hash bucket.

public uint predicate_impl_lookup_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint predicate_impl_lookup_capacity(uint predicate_count)
{
    return max(predicate_count * 2u, 1u);
}

public uint predicate_impl_lookup_bucket(
    uint bound_decl_id,
    uint subject_type,
    uint argument_count,
    uint argument0_type,
    uint argument1_type,
    uint predicate_count)
{
    uint hash = predicate_impl_lookup_mix(bound_decl_id ^ 0x9e3779b9u);
    hash ^= predicate_impl_lookup_mix(subject_type ^ 0xc2b2ae35u);
    hash ^= predicate_impl_lookup_mix(argument_count ^ 0x85ebca6bu);
    hash ^= predicate_impl_lookup_mix(argument0_type ^ 0x27d4eb2fu);
    hash ^= predicate_impl_lookup_mix(argument1_type ^ 0x165667b1u);
    return predicate_impl_lookup_mix(hash) % predicate_impl_lookup_capacity(predicate_count);
}
