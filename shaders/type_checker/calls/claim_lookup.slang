// Exact index shared by generic and const-generic call claims. Bucket
// collisions are resolved by intrusive row chains; consumers always compare
// the complete `(callee, slot)` key before accepting a row.

public uint call_claim_lookup_mix(uint value)
{
    value ^= value >> 16u;
    value *= 0x7feb352du;
    value ^= value >> 15u;
    value *= 0x846ca68bu;
    value ^= value >> 16u;
    return value;
}

public uint call_claim_lookup_capacity(uint claim_count)
{
    return max(claim_count, 1u);
}

public uint call_claim_lookup_bucket(uint callee, uint slot, uint claim_count)
{
    uint hash = call_claim_lookup_mix(callee ^ 0x9e3779b9u);
    hash ^= call_claim_lookup_mix(slot ^ 0xc2b2ae35u);
    return call_claim_lookup_mix(hash) % call_claim_lookup_capacity(claim_count);
}
