// Compact hash-bucket index for callable predicate bounds. Bucket collisions
// are resolved by an intrusive chain and every consumer verifies the complete
// owner token, so hashing changes performance but never predicate semantics.

public uint predicate_owner_lookup_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint predicate_owner_lookup_capacity(uint predicate_count)
{
    return max(predicate_count * 2u, 1u);
}

public uint predicate_owner_lookup_bucket(uint owner_token, uint predicate_count)
{
    return predicate_owner_lookup_mix(owner_token) %
           predicate_owner_lookup_capacity(predicate_count);
}
