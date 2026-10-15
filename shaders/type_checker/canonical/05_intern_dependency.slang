// One interning round over the resident dependency page, as 01_intern over
// a job's candidates: round 0 is direct over every node of the page, later
// rounds are indirect over the frontier (02_round_args closes each round).
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_dependency;
import dependency_interface;

// Two frontier lists of half the buffer each; round r reads list r & 1 and
// appends to list (r + 1) & 1.
RWStructuredBuffer<uint> canonical_frontier;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    uint round = ct_counts[CT_COUNT_ROUND];
    uint words; uint stride;
    canonical_frontier.GetDimensions(words, stride);
    uint list = words / 2u;
    uint node;
    if (round == 0u)
    {
        if (i >= dependency_type_count()) return;
        // Children have smaller indices than their parents: leaves first.
        node = i;
        if (ct_dependency_state(node) != CT_PENDING) return;
    }
    else
    {
        if (i >= ct_counts[CT_COUNT_PENDING]) return;
        node = canonical_frontier[(round & 1u) * list + i];
    }
    uint id = canonical_intern_dependency(node, ct_counts[CT_COUNT_FINAL] != 0u);
    if (id != CT_PENDING)
    {
        // Release fence first, as ct_publish_candidate.
        DeviceMemoryBarrier();
        uint index = ct_dependency_index(node);
        if (index != 0xffffffffu) canonical_dependency_type[index] = id;
        return;
    }
    uint next = (round + 1u) & 1u;
    uint slot;
    InterlockedAdd(ct_counts[CT_COUNT_FRONTIER + next], 1u, slot);
    if (slot < list) canonical_frontier[next * list + slot] = node;
}
