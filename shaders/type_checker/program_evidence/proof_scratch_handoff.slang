// INTERIM (P7): a proof stage split over several dispatches per chunk of at
// most THREAD_SCRATCH_SLOTS rows hands each row's progress from one dispatch
// to the next in the row's thread-scratch slot (SCRATCH_PPS_HANDOFF). The
// first dispatch tags the slot with the stage's phase, the row and the
// proof-store serial; every later dispatch checks the tag, so a slot that
// the same chunk's first dispatch did not write (chunk-order coupling broke)
// fails the batch with detail 191. The last dispatch consumes the slot.
import thread_scratch;
import type_checker.program_evidence.abi;
import type_checker.program_evidence.proof_store_abi;
import type_checker.owned_type_constraint_contract;

static const uint PPS_HANDOFF_CONSUMED = 0u;

public void pps_handoff_tag(uint stage, uint row, uint outcome)
{ scratch_set_cell(SCRATCH_PPS_HANDOFF, uint4(outcome, stage, row, proof_store_params.serial)); }
// The outcome an earlier dispatch of this chunk recorded for `row`.
public EvidenceStatus pps_handoff_outcome(uint stage, uint row, out uint outcome)
{
    uint4 cell = scratch_cell(SCRATCH_PPS_HANDOFF);
    outcome = cell.x;
    return cell.y == stage && cell.z == row && cell.w == proof_store_params.serial &&
        outcome != PPS_HANDOFF_CONSUMED ? pev_ok() : pev_invalid(191u, row, outcome);
}
public void pps_handoff_consume()
{ scratch_set_word(SCRATCH_PPS_HANDOFF, 0u, PPS_HANDOFF_CONSUMED); }

// An owned constraint state in 8 cells from `cell`. Its frame stays in place.
public void pps_handoff_save_state(uint cell, OwnedConstraintState state)
{
    scratch_set_cell(cell, uint4(state.status.state, state.status.detail,
        state.status.required, state.status.available));
    scratch_set_cell(cell + 1u, uint4(state.limits.depth, state.limits.pair_visits,
        state.limits.occurs_visits, state.limits.substitution_steps));
    scratch_set_cell(cell + 2u, uint4(state.work.pair_visits, state.work.occurs_visits,
        state.work.substitution_steps, state.identity_capacity));
    scratch_set_cell(cell + 3u, state.counts);
    scratch_set_cell(cell + 4u, state.bound);
    scratch_set_cell(cell + 5u, state.seen);
    scratch_set_cell(cell + 6u, uint4(state.owners, state.node_capacities));
    scratch_set_cell(cell + 7u, uint4(state.overlap, state.finished, state.frame, 0u));
}
public OwnedConstraintState pps_handoff_load_state(uint cell)
{
    OwnedConstraintState state;
    uint4 value = scratch_cell(cell);
    state.status.state = value.x; state.status.detail = value.y;
    state.status.required = value.z; state.status.available = value.w;
    value = scratch_cell(cell + 1u);
    state.limits.depth = value.x; state.limits.pair_visits = value.y;
    state.limits.occurs_visits = value.z; state.limits.substitution_steps = value.w;
    value = scratch_cell(cell + 2u);
    state.work.pair_visits = value.x; state.work.occurs_visits = value.y;
    state.work.substitution_steps = value.z; state.identity_capacity = value.w;
    state.counts = scratch_cell(cell + 3u);
    state.bound = scratch_cell(cell + 4u);
    state.seen = scratch_cell(cell + 5u);
    value = scratch_cell(cell + 6u);
    state.owners = value.xy; state.node_capacities = value.zw;
    value = scratch_cell(cell + 7u);
    state.overlap = value.x; state.finished = value.y; state.frame = value.z;
    return state;
}
