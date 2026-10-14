// Slot owners allocate canonical IDs and publish their records.
import type_checker.canonical.canonical_types;
import type_checker.checked_type_graph;
import type_checker.constant_atoms;
import constant_value;
import primitive_types;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint candidate = dtid.x + dtid.y * 16776960u;
    if (candidate >= canonical_candidate_capacity() ||
        canonical_cand_state[candidate] != CAND_OWNER) return;
    canonical_cand_state[candidate] = CAND_DONE;
    uint4 a = canonical_cand_key_a[candidate];
    uint4 b = canonical_cand_key_b[candidate];
    uint id; InterlockedAdd(canonical_counts[0u], 1u, id);
    uint base = 0u;
    uint capacity; uint stride;
    canonical_ct_args.GetDimensions(capacity, stride);
    if (b.y != 0u) InterlockedAdd(canonical_counts[1u], b.y, base);
    if (id >= canonical_record_capacity() || base > capacity || b.y > capacity - base)
    {
        // The slot keeps naming this candidate, whose key stays valid, so
        // equal candidates in later rounds still resolve to UNKNOWN.
        InterlockedOr(canonical_counts[3u], 2u);
        set_canonical_of_candidate(candidate, CANON_UNKNOWN);
        return;
    }
    for (uint i = 0u; i < b.y; i++) canonical_ct_args[base + i] = canonical_cand_args[b.z + i];
    canonical_ct_key_a[id] = a;
    canonical_ct_key_b[id] = uint4(b.x, b.y, base, b.w);
    canonical_ct_rep[id] = candidate;
    canonical_ct_slot[canonical_cand_slot[candidate]] = id;
    set_canonical_of_candidate(candidate, id);
}
