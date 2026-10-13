// Compact exact index for trait and implementation method contracts. Hash
// collisions share a bucket chain; lookups always compare both key fields.

public uint method_contract_lookup_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint method_contract_lookup_capacity(uint method_count)
{
    return max(method_count * 2u, 1u);
}

public uint method_contract_lookup_bucket(uint owner, uint name_id, uint method_count)
{
    uint hash = method_contract_lookup_mix(owner ^ 0x9e3779b9u);
    hash ^= method_contract_lookup_mix(name_id ^ 0xc2b2ae35u);
    return method_contract_lookup_mix(hash) % method_contract_lookup_capacity(method_count);
}
