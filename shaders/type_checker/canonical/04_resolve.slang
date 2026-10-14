// Candidates that matched an equal key adopt its canonical ID. A matched
// candidate was published in the preceding dispatch or an earlier round.
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
        canonical_cand_state[candidate] != CAND_MATCHED) return;
    canonical_cand_state[candidate] = CAND_DONE;
    uint winner = canonical_cand_winner[candidate];
    set_canonical_of_candidate(candidate, (winner & SLOT_CANDIDATE_BIT) != 0u
        ? canonical_of_candidate(winner & ~SLOT_CANDIDATE_BIT) : winner);
}
