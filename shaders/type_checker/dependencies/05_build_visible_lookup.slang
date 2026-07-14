// Build a parallel exact-name candidate table for imported declarations.

import atomics;
import gpu_index;
import status;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> dependency_visible_total;
StructuredBuffer<uint> dependency_visible_owner_module;
StructuredBuffer<uint> dependency_visible_decl;
StructuredBuffer<uint> dependency_declaration_words;
RWStructuredBuffer<uint> dependency_visible_lookup;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint DECL_WORDS = 14u;
static const uint ERR_BAD_HIR = 6u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint mix(uint hash, uint value)
{
    hash ^= value;
    hash *= 16777619u;
    return hash;
}

uint visible_hash(uint visible_i)
{
    uint declaration_i = dependency_visible_decl[visible_i];
    uint base = declaration_i * DECL_WORDS;
    uint hash = mix(2166136261u, dependency_visible_owner_module[visible_i]);
    hash = mix(hash, dependency_declaration_words[base + 5u]);
    hash = mix(hash, dependency_declaration_words[base + 1u]);
    return mix(hash, dependency_declaration_words[base + 2u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint visible_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (visible_i >= min(dependency_visible_total[0u], gParams.visible_capacity))
        return;
    uint declaration_i = dependency_visible_decl[visible_i];
    if (declaration_i >= gParams.declaration_count ||
        dependency_visible_owner_module[visible_i] == INVALID)
        return;
    uint mask = gParams.lookup_capacity - 1u;
    uint slot = visible_hash(visible_i) & mask;
    for (uint probe = 0u; probe < gParams.lookup_capacity; probe += 1u)
    {
        uint prior = atomic_u32_compare_exchange(
            dependency_visible_lookup, slot, INVALID, visible_i);
        if (prior == INVALID)
            return;
        slot = (slot + 1u) & mask;
    }
    record_min_token_error(status, 0u, ERR_BAD_HIR, visible_i);
}
