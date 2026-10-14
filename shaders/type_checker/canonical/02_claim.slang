// Claim an open-addressing slot for each proposed key, or match an equal key
// already in the table. Occupying candidates wrote their keys in the
// preceding dispatch, so comparing against them never waits.
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
        canonical_cand_state[candidate] != CAND_PROPOSED) return;
    uint slots = canonical_slot_capacity();
    uint hash = canonical_cand_key_b[candidate].w;
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint slot = (hash + probe) & (slots - 1u);
        uint value = canonical_ct_slot[slot];
        if (value == 0u)
        {
            InterlockedCompareExchange(canonical_ct_slot[slot], 0u,
                SLOT_CANDIDATE_BIT | candidate, value);
            if (value == 0u)
            {
                canonical_cand_slot[candidate] = slot;
                canonical_cand_state[candidate] = CAND_OWNER;
                return;
            }
        }
        bool equal = (value & SLOT_CANDIDATE_BIT) != 0u
            ? canonical_candidate_matches_candidate(candidate, value & ~SLOT_CANDIDATE_BIT)
            : canonical_candidate_matches_record(candidate, value);
        if (equal)
        {
            canonical_cand_winner[candidate] = value;
            canonical_cand_state[candidate] = CAND_MATCHED;
            return;
        }
    }
    InterlockedOr(canonical_counts[3u], 1u);
    set_canonical_of_candidate(candidate, CANON_UNKNOWN);
    canonical_cand_state[candidate] = CAND_DONE;
}
