// Parallel open-address construction of the method index of the resident
// dependency page (dependency_method_index): one thread per member row.
// Each table has at least twice as many slots as the page has members, so an
// insertion always finds a free slot.

import dependency_interface;
import semantic_interface_layout;
import atomics;
import gpu_index;

RWStructuredBuffer<uint> dependency_method_lookup;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

void insert(uint first, uint capacity, uint hash, uint row)
{
    uint mask = capacity - 1u;
    for (uint probe = 0u; probe < capacity; probe += 1u)
    {
        uint slot = first + ((hash + probe) & mask);
        if (atomic_u32_compare_exchange(dependency_method_lookup, slot, INVALID, row) == INVALID)
            return;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (row >= dependency_member_count()) return;
    uint length; uint stride;
    dependency_method_lookup.GetDimensions(length, stride);
    uint capacity = length >> 1u;
    if (capacity == 0u) return;
    bool implementation = dependency_public_implementation_method(row);
    if (!implementation && !dependency_trait_requirement(row)) return;
    uint base = row * SEMANTIC_INTERFACE_MEMBER_WORDS;
    uint library; uint unit; uint local;
    if (!dependency_contract_owner_identity(dependency_member_word(base), library, unit, local)) return;
    insert(0u, capacity,
        dependency_method_identity_hash(library, unit, dependency_member_word(base + 9u)), row);
    if (implementation)
        insert(capacity, capacity,
            dependency_method_name_hash(dependency_member_word(base + 3u), dependency_member_word(base + 4u)), row);
}
