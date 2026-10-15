import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.catalog_index;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_work;
import type_checker.program_evidence.proof_goal_equality;
import type_checker.program_evidence.owned_implementation_graph;
import type_checker.program_evidence.implementation_goal_matching;
import type_checker.program_evidence.proof_binding_materialization;
import type_checker.program_evidence.proof_term_graph;
import type_checker.owned_type_constraint_contract;
import type_checker.owned_type_constraint_engine;
import type_checker.scoped_type_hash;
import thread_scratch;

public static const uint PPS_WORK_SELECTED = 10u;
public static const uint PPS_WORK_FAILED = 11u;
public static const uint PPS_EVENT_READY = 1u;
public static const uint PPS_EVENT_PROVEN = 2u;
public static const uint PPS_EVENT_FAILED = 3u;

public OwnedConstraintLimits pps_matching_limits()
{
    OwnedConstraintLimits limits;
    limits.depth = PEV_DEPTH_LIMIT; limits.pair_visits = PEV_VISIT_LIMIT;
    limits.occurs_visits = PEV_VISIT_LIMIT; limits.substitution_steps = PEV_VISIT_LIMIT;
    return limits;
}
public EvidenceStatus pps_enqueue(uint work, uint event)
{
    uint row;
    EvidenceStatus status = pps_reserve(PPS_REDUCTION_QUEUE, 1u, work, row);
    if (status.state != PEV_VALID) return status;
    return pps_write2(PPS_REDUCTION_QUEUE, row, 0u, uint2(work, event)) ? pev_ok() :
        pev_invalid(1u, work, PPS_REDUCTION_QUEUE);
}

// The coherent catalog admits at most one matching implementation. Complete
// every bounded chain anyway: malformed links and exhausted work are errors.
public EvidenceStatus pps_find_implementation(uint goal, bool coarse,
    out uint selected, out OwnedConstraintState selected_state)
{
    selected = PEV_INVALID; selected_state = (OwnedConstraintState)0;
    uint4 low; uint4 high; uint implementations; uint rows; uint buckets;
    uint candidate; uint table = coarse ? 11u : 6u;
    if (!pps_read8(PPS_GOALS, goal, low, high) ||
        !pev_catalog_count(9u, implementations) || !pev_work_counts(rows, buckets))
        return pev_invalid(1u, goal, table);
    uint hash = coarse ? pev_coarse_implementation_hash(low.x, high.x) : high.y;
    if (!pev_output_read(coarse ? 12u : 7u, hash & (buckets - 1u), 0u, candidate))
        return pev_invalid(1u, goal, table);
    [loop]
    for (uint examined = 0u; candidate != PEV_INVALID; examined++)
    {
        if (examined == PEV_CHAIN_LIMIT) return pev_limit(8u, goal, examined + 1u, PEV_CHAIN_LIMIT);
        uint4 link;
        if (candidate >= implementations || !pev_output_read4(table, candidate, 0u, link) ||
            link.z != candidate || link.w != 1u) return pev_invalid(70u, goal, candidate);
        if (link.x == hash)
        {
            // A candidate never matches into the frame the selected state holds.
            bool matches; OwnedConstraintState current;
            uint frame = owned_constraint_frame(
                selected != PEV_INVALID && selected_state.frame == owned_constraint_frame(0u) ? 1u : 0u);
            EvidenceStatus status = pev_match_implementation_goal(candidate, goal,
                pps_matching_limits(), frame, matches, current);
            if (status.state != PEV_VALID) return status;
            if (matches)
            {
                if (selected != PEV_INVALID && selected != candidate)
                {
                    EvidenceStatus conflict = pev_invalid(0u, selected, candidate);
                    conflict.state = PEV_COHERENCE_CONFLICT; return conflict;
                }
                selected = candidate; selected_state = current;
            }
        }
        candidate = link.y;
    }
    return pev_ok();
}
public EvidenceStatus pps_find_assumption(uint context, uint goal, out uint selected)
{
    selected = PEV_INVALID;
    uint4 low; uint4 high; uint assumptions; uint buckets; uint candidate;
    uint owner; bool closed;
    if (!pps_read8(PPS_GOALS, goal, low, high) || !pev_table_count(14u, assumptions) ||
        !pev_bucket_count(assumptions, buckets) || !pev_context_goal_scope(context, owner, closed))
        return pev_invalid(1u, goal, context);
    uint hash = scoped_type_hash_mix(high.y, context);
    if (!pev_output_read(9u, hash & (buckets - 1u), 0u, candidate))
        return pev_invalid(1u, goal, context);
    uint best_atom = PEV_INVALID;
    [loop]
    for (uint examined = 0u; candidate != PEV_INVALID; examined++)
    {
        if (examined == PEV_CHAIN_LIMIT) return pev_limit(8u, goal, examined + 1u, PEV_CHAIN_LIMIT);
        uint4 index; uint4 row;
        if (candidate >= assumptions || !pev_output_read4(8u, candidate, 0u, index) ||
            index.z != candidate || index.w != 1u || !pev_read4(14u, candidate, 0u, row))
            return pev_invalid(70u, goal, candidate);
        if (index.x == high.y && row.x == context)
        {
            bool equal;
            EvidenceStatus status = pps_assumption_equals_goal(candidate, row.y, row.z, owner, goal,
                closed, equal);
            if (status.state != PEV_VALID) return status;
            if (equal)
            {
                uint atom;
                if (!pev_word(8u, row.y, 0u, atom)) return pev_invalid(1u, goal, row.y);
                if (selected == PEV_INVALID || atom < best_atom)
                { selected = candidate; best_atom = atom; }
            }
        }
        candidate = index.y;
    }
    return pev_ok();
}

public EvidenceStatus pps_write_substitution(uint implementation, uint goal, uint context,
    inout OwnedConstraintState state, out uint substitution)
{
    substitution = PEV_INVALID; uint4 head; uint4 owner;
    uint4 span;
    if (!pev_read4(9u, implementation, 0u, head) || !pev_read4(2u, head.y, 0u, owner) ||
        !pev_read4(2u, head.y, 4u, span) || span.y != state.counts.x + state.counts.y || span.y > 64u)
        return pev_invalid(68u, implementation, goal);
    uint visible_owner; bool require_closed;
    if (!pev_context_goal_scope(context, visible_owner, require_closed))
        return pev_invalid(68u, implementation, context);
    uint bindings = 0u;
    uint previous = PEV_INVALID;
    // Unit 0 reserves the substitution row, unit 1 the binding span, and unit
    // 2 + i writes binding i after reserving its nodes: one reservation site.
    [loop]
    for (uint unit = 0u; unit < span.y + 2u; unit++)
    {
        uint table = unit == 0u ? PPS_SUBSTITUTIONS : PPS_BINDINGS;
        uint count = unit == 0u ? 1u : span.y; uint subject = implementation;
        uint i = unit - 2u;
        uint atom = PEV_INVALID; uint domain = PEV_INVALID;
        OwnedConstraintBindingRequest request = (OwnedConstraintBindingRequest)0;
        if (unit >= 2u)
        {
            [loop]
            for (uint j = 0u; j < span.y; j++)
            {
                uint4 parameter;
                if (!pev_read4(3u, span.x + j, 0u, parameter) || parameter.x != head.y || parameter.w > 1u)
                    return pev_invalid(68u, implementation, span.x + j);
                if ((i == 0u || parameter.y > previous) && parameter.y < atom)
                { atom = parameter.y; domain = parameter.w; }
            }
            uint index;
            if (atom == PEV_INVALID || CatalogImplementationPatternGraph.owned_parameter(
                head.y, atom, domain == 1u, index) != OWNED_PARAMETER_BINDABLE)
                return pev_invalid(68u, implementation, atom);
            if (!owned_constraint_binding<CatalogImplementationPatternGraph, SolverProofTermGraph>(
                state, domain == 1u, index, request))
                return state.status.state == OWNED_CONSTRAINT_MATCHED
                    ? pev_invalid(68u, implementation, PEV_INVALID)
                    : pev_owned_constraint_status(state.status, implementation);
            table = PPS_TERM_NODES; count = request.target_count; subject = atom;
        }
        EvidenceStatus status;
        uint first = 0u;
        if (unit < 2u || count != 0u)
        {
            status = pps_reserve(table, count, subject, first);
            if (status.state != PEV_VALID) return status;
        }
        if (unit < 2u)
        {
            if (unit == 0u) substitution = first; else bindings = first;
            continue;
        }
        uint4 allocation = uint4(first, request.target_count, 0u, 0u);
        uint2 value; bool closed;
        status = pps_materialize_binding_request<SolverProofTermSink>(request, atom,
            visible_owner, require_closed, allocation, value, closed);
        if (status.state != PEV_VALID) return status;
        if (!pps_write8(PPS_BINDINGS, bindings + i,
            uint4(substitution, atom, value.x, value.y), allocation))
            return pev_invalid(68u, implementation, atom);
        previous = atom;
    }
    return pps_write4(PPS_SUBSTITUTIONS, substitution, 0u,
        uint4(implementation, bindings, span.y, goal)) ? pev_ok() : pev_invalid(1u, substitution, implementation);
}

// INTERIM (P7): selection takes the exact implementation, then a caller
// assumption, then the generic implementation. It runs as four dispatches per
// chunk of at most THREAD_SCRATCH_SLOTS work rows (ProofKernels::
// record_selection), so no kernel inlines more than one search: the exact
// match (phase 53), the assumption search, the generic match (phase 65, the
// same kernel), then the finish. A work's slot carries the outcome between
// them in SCRATCH_PPS_SELECTION: (outcome, selected row, work, serial), the
// work key, and the matched constraint state, whose frame also stays put
// because later phases skip a work that is already selected. Each later
// phase checks the tag and fails the batch with detail 191 on a slot this
// chunk's exact match did not write; the finish consumes the slot.
public static const uint PPS_SELECT_PHASE_EXACT = 53u;
public static const uint PPS_SELECT_PHASE_GENERIC = 65u;
static const uint PPS_SELECT_CONSUMED = 0u;
static const uint PPS_SELECT_SKIP = 1u;
static const uint PPS_SELECT_EXACT_NONE = 2u;
static const uint PPS_SELECT_ASSUMPTION_NONE = 3u;
static const uint PPS_SELECT_IMPLEMENTATION = 4u;
static const uint PPS_SELECT_READY = 5u;
static const uint PPS_SELECT_MISSING = 6u;

void pps_selection_save(uint work, uint outcome, uint selected)
{ scratch_set_cell(SCRATCH_PPS_SELECTION, uint4(outcome, selected, work, proof_store_params.serial)); }
// The outcome a previous phase of this chunk recorded for `work`, or a lost
// handoff (chunk-order coupling broke) as a loud batch failure.
EvidenceStatus pps_selection_load(uint work, out uint outcome, out uint selected)
{
    uint4 cell = scratch_cell(SCRATCH_PPS_SELECTION);
    outcome = cell.x; selected = cell.y;
    return cell.z == work && cell.w == proof_store_params.serial && outcome != PPS_SELECT_CONSUMED ?
        pev_ok() : pev_invalid(191u, work, outcome);
}
void pps_selection_save_state(OwnedConstraintState state)
{
    uint cell = SCRATCH_PPS_SELECTION + 2u;
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
OwnedConstraintState pps_selection_load_state()
{
    uint cell = SCRATCH_PPS_SELECTION + 2u;
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

// Exact (coarse false) or generic implementation match. The exact phase
// admits the work row; the generic phase runs only for works that neither an
// exact implementation nor an assumption selected.
public EvidenceStatus pps_select_implementation(uint work, bool coarse)
{
    uint4 key; uint outcome; uint selected;
    if (coarse)
    {
        EvidenceStatus handoff = pps_selection_load(work, outcome, selected);
        if (handoff.state != PEV_VALID) return handoff;
        if (outcome != PPS_SELECT_ASSUMPTION_NONE) return pev_ok();
        key = scratch_cell(SCRATCH_PPS_SELECTION + 1u);
    }
    else
    {
        uint4 selection; uint4 completion; uint4 source;
        if (!pps_work_read(work, key, selection, completion, source)) return pev_invalid(1u, work, PPS_WORK);
        if (key.z == PPS_WORK_ALIAS)
        { pps_selection_save(work, PPS_SELECT_SKIP, PEV_INVALID); return pev_ok(); }
        if (key.z != PPS_WORK_NEW || key.w != work) return pev_invalid(70u, work, key.z);
        scratch_set_cell(SCRATCH_PPS_SELECTION + 1u, key);
    }
    uint implementation; OwnedConstraintState state;
    EvidenceStatus status = pps_find_implementation(key.y, coarse, implementation, state);
    if (status.state != PEV_VALID) return status;
    if (implementation != PEV_INVALID) pps_selection_save_state(state);
    pps_selection_save(work, implementation != PEV_INVALID ? PPS_SELECT_IMPLEMENTATION :
        coarse ? PPS_SELECT_MISSING : PPS_SELECT_EXACT_NONE, implementation);
    return pev_ok();
}
public EvidenceStatus pps_select_assumption(uint work)
{
    uint outcome; uint selected;
    EvidenceStatus status = pps_selection_load(work, outcome, selected);
    if (status.state != PEV_VALID || outcome != PPS_SELECT_EXACT_NONE) return status;
    uint4 key = scratch_cell(SCRATCH_PPS_SELECTION + 1u);
    uint assumption;
    status = pps_find_assumption(key.x, key.y, assumption);
    if (status.state != PEV_VALID) return status;
    pps_selection_save(work, assumption != PEV_INVALID ? PPS_SELECT_READY : PPS_SELECT_ASSUMPTION_NONE,
        assumption);
    return pev_ok();
}
public EvidenceStatus pps_select_finish(uint work)
{
    uint outcome; uint found;
    EvidenceStatus status = pps_selection_load(work, outcome, found);
    if (status.state != PEV_VALID) return status;
    scratch_set_word(SCRATCH_PPS_SELECTION, 0u, PPS_SELECT_CONSUMED);
    if (outcome == PPS_SELECT_SKIP) return pev_ok();
    if (outcome < PPS_SELECT_IMPLEMENTATION || outcome > PPS_SELECT_MISSING)
        return pev_invalid(191u, work, outcome);
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source)) return pev_invalid(1u, work, PPS_WORK);
    uint event = 0u;
    if (outcome == PPS_SELECT_READY)
    {
        key.z = PPS_WORK_READY; selected = uint4(PEV_INVALID, found, 0u, 0u); event = PPS_EVENT_READY;
    }
    if (outcome == PPS_SELECT_MISSING) { key.z = PPS_WORK_MISSING; event = PPS_EVENT_FAILED; }
    if (event == 0u)
    {
        OwnedConstraintState state = pps_selection_load_state();
        uint substitution;
        status = pps_write_substitution(found, key.y, key.x, state, substitution);
        if (status.state != PEV_VALID) return status;
        key.z = PPS_WORK_SELECTED; selected = uint4(found, substitution, 0u, 0u);
    }
    // One work write and one enqueue site for the ready, missing and
    // selected outcomes (a missing work rewrites only its key).
    bool written = event == PPS_EVENT_FAILED ? pps_write4(PPS_WORK, work, 0u, key) :
        pps_work_write(work, key, selected, completion, source);
    if (!written) return pev_invalid(1u, work, PPS_WORK);
    return event == 0u ? pev_ok() : pps_enqueue(work, event);
}
