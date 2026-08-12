// Hash-bucket selection shared by method index construction, validation, and
// call resolution. Exact receiver arguments and module visibility are checked
// while traversing the selected bucket, so hash collisions remain correct.

public uint method_lookup_capacity(uint method_capacity)
{
    return max(method_capacity * 2u, 1u);
}

public uint method_lookup_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint method_lookup_bucket(
    uint receiver_tag,
    uint receiver_payload_key,
    uint receiver_arg_count,
    uint receiver_arg_hash,
    uint name_id,
    uint method_capacity)
{
    uint hash = method_lookup_mix(receiver_tag ^ 0x9e3779b9u);
    hash ^= method_lookup_mix(receiver_payload_key ^ 0xc2b2ae35u);
    hash ^= method_lookup_mix(receiver_arg_count ^ 0x85ebca6bu);
    hash ^= method_lookup_mix(receiver_arg_hash ^ 0x27d4eb2fu);
    hash ^= method_lookup_mix(name_id ^ 0x165667b1u);
    return method_lookup_mix(hash) % method_lookup_capacity(method_capacity);
}
