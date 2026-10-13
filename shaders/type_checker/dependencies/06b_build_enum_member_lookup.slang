#include "normalized_member_lookup.slang"
import atomics;
import status;
// Reuse visibility's table only after its consumers finish on this page.
// Capacity is at least twice the dependency declaration count.
RWStructuredBuffer<uint> dependency_visible_lookup;
RWStructuredBuffer<uint> status;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint declaration = dtid.x + dtid.y * 16776960u;
    if (declaration >= dependency_declaration_count()) return;
    uint base = declaration * 14u;
    if (dependency_declaration_word(base + 6u) != 9u) return;
    uint parent = dependency_declaration_word(base + 10u);
    if (parent >= dependency_declaration_count() || dependency_declaration_word(parent * 14u + 6u) != 7u) return;
    uint mask = gParams.lookup_capacity - 1u;
    uint slot = normalized_member_hash(parent, dependency_declaration_word(base + 1u),
        dependency_declaration_word(base + 2u)) & mask;
    for (uint probe = 0u; probe < gParams.lookup_capacity; probe++)
    {
        if (atomic_u32_compare_exchange(dependency_visible_lookup, slot, INVALID, declaration) == INVALID) return;
        slot = (slot + 1u) & mask;
    }
    record_min_token_error(status, 0u, 6u, 0x414d0001u);
}
