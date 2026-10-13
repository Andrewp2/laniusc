// Index concrete trait implementations by complete scoped structure. Hashes
// select a bucket; every consumer still compares all ordered type graphs.
import type_checker.predicates.trait_reference;

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

public uint predicate_impl_lookup_bucket(uint trait_reference, uint argument_count,
    uint type_hash, uint predicate_count)
{
    uint4 identity = trait_reference_identity(trait_reference);
    uint hash = predicate_impl_lookup_mix(identity.x ^ 0x9e3779b9u);
    hash ^= predicate_impl_lookup_mix(identity.y ^ 0x85ebca6bu);
    hash ^= predicate_impl_lookup_mix(identity.z ^ 0xc2b2ae35u);
    hash ^= predicate_impl_lookup_mix(identity.w ^ 0x165667b1u);
    hash ^= predicate_impl_lookup_mix(argument_count ^ 0x85ebca6bu);
    hash ^= predicate_impl_lookup_mix(type_hash ^ 0x27d4eb2fu);
    return predicate_impl_lookup_mix(hash) % predicate_impl_lookup_capacity(predicate_count);
}
