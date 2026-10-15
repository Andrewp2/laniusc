// Negative control for canonical_intern_stress: the same lookup-first small
// key protocol with plain (non-coherent) buffers and no fences. Duplicates
// here show that the stress test can observe a broken publication order.
struct Params
{
    uint lanes;
    uint distinct;
    uint seed;
    uint mode;
};
ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint4> nc_head;
RWStructuredBuffer<uint> nc_slot;
RWStructuredBuffer<uint> nc_counts;
RWStructuredBuffer<uint> stress_result;
RWStructuredBuffer<uint> stress_errors;

uint mix32(uint x)
{
    x ^= x >> 16u; x *= 0x7feb352du;
    x ^= x >> 15u; x *= 0x846ca68bu;
    return x ^ (x >> 16u);
}

uint slot_count() { uint n; uint s; nc_slot.GetDimensions(n, s); return n; }

uint key_hash(uint4 key) { return mix32(key.x ^ mix32(key.y ^ mix32(key.z ^ mix32(key.w)))); }

uint intern(uint4 key)
{
    uint slots = slot_count();
    uint slot = key_hash(key) & (slots - 1u);
    uint record = 0u;
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = nc_slot[slot];
        if (value == 0u)
        {
            if (record == 0u)
            {
                InterlockedAdd(nc_counts[0u], 1u, record);
                nc_head[record] = key;
            }
            InterlockedCompareExchange(nc_slot[slot], 0u, record, value);
            if (value == 0u) return record;
        }
        if (all(nc_head[value] == key)) return value;
        slot = (slot + 1u) & (slots - 1u);
    }
    return 0u;
}

void intern_chain(uint lane)
{
    uint group = (gParams.seed & 1u) != 0u ? lane % gParams.distinct
        : (lane / max(gParams.lanes / gParams.distinct, 1u));
    uint chain = mix32(group ^ (gParams.seed * 0x9e3779b9u));
    uint id = intern(uint4(1u, chain % 61u, 0u, 0u));
    for (uint level = 1u; level <= 1u + chain % 12u && id != 0u; level++)
        id = intern(uint4(2u + ((chain >> (2u * level)) & 3u), id, level % 3u, 0u));
    stress_result[lane] = id;
}

void validate_slot(uint slot)
{
    uint record = nc_slot[slot];
    if (record == 0u) return;
    InterlockedAdd(stress_errors[5u], 1u);
    uint slots = slot_count();
    uint probe = key_hash(nc_head[record]) & (slots - 1u);
    for (uint step = 0u; step < slots && probe != slot; step++)
    {
        uint other = nc_slot[probe];
        if (other == 0u) { InterlockedAdd(stress_errors[1u], 1u); return; }
        if (all(nc_head[other] == nc_head[record])) { InterlockedAdd(stress_errors[0u], 1u); return; }
        probe = (probe + 1u) & (slots - 1u);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    if (gParams.mode == 0u)
    {
        if (i < gParams.lanes) intern_chain(i);
        return;
    }
    if (i < slot_count()) validate_slot(i);
}
