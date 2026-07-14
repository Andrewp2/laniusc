// Parallel open-address construction for dependency module identities.

import atomics;
import gpu_index;

struct Params
{
    uint module_count;
    uint lookup_capacity;
    uint import_capacity;
    uint source_len;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> dependency_module_words;
StructuredBuffer<uint> dependency_module_segment_words;
RWStructuredBuffer<uint> dependency_module_lookup;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint MODULE_WORDS = 2u;
static const uint SEGMENT_WORDS = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint ERR_BAD_HIR = 6u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint mix(uint hash, uint value)
{
    hash ^= value;
    hash *= 16777619u;
    return hash;
}

uint module_hash(uint module_i)
{
    uint base = module_i * MODULE_WORDS;
    uint first = dependency_module_words[base + 0u];
    uint count = dependency_module_words[base + 1u];
    uint hash = mix(2166136261u, count);
    for (uint segment_i = 0u; segment_i < 8u; segment_i += 1u)
    {
        if (segment_i >= count)
            break;
        uint segment = (first + segment_i) * SEGMENT_WORDS;
        hash = mix(hash, dependency_module_segment_words[segment + 0u]);
        hash = mix(hash, dependency_module_segment_words[segment + 1u]);
    }
    return hash;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint module_i = linear_thread_id(dtid);
    if (module_i >= gParams.module_count || gParams.lookup_capacity == 0u)
        return;
    uint mask = gParams.lookup_capacity - 1u;
    uint slot = module_hash(module_i) & mask;
    for (uint probe = 0u; probe < gParams.lookup_capacity; probe += 1u)
    {
        uint prior = atomic_u32_compare_exchange(
            dependency_module_lookup,
            slot,
            INVALID,
            module_i);
        if (prior == INVALID)
            return;
        slot = (slot + 1u) & mask;
    }
    atomic_u32_or(status, 0u, 1u);
    atomic_u32_min(status, 1u, module_i);
    atomic_u32_min(status, 2u, ERR_BAD_HIR);
}
