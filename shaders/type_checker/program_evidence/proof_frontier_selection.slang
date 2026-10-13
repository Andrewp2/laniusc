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
            bool matches; OwnedConstraintState current;
            EvidenceStatus status = pev_match_implementation_goal(candidate, goal,
                pps_matching_limits(), matches, current);
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
            EvidenceStatus status = pps_predicate_equals_goal(row.y, row.z, owner, goal, closed, equal);
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
    uint bindings;
    EvidenceStatus status = pps_reserve(PPS_SUBSTITUTIONS, 1u, implementation, substitution);
    if (status.state != PEV_VALID) return status;
    status = pps_reserve(PPS_BINDINGS, span.y, implementation, bindings);
    if (status.state != PEV_VALID) return status;
    uint previous = PEV_INVALID;
    [loop]
    for (uint i = 0u; i < span.y; i++)
    {
        uint atom = PEV_INVALID; uint domain = PEV_INVALID;
        [loop]
        for (uint j = 0u; j < span.y; j++)
        {
            uint4 parameter;
            if (!pev_read4(3u, span.x + j, 0u, parameter) || parameter.x != head.y || parameter.w > 1u)
                return pev_invalid(68u, implementation, span.x + j);
            if ((i == 0u || parameter.y > previous) && parameter.y < atom)
            { atom = parameter.y; domain = parameter.w; }
        }
        uint index; OwnedConstraintBindingRequest request;
        if (atom == PEV_INVALID || CatalogImplementationPatternGraph.owned_parameter(
            head.y, atom, domain == 1u, index) != OWNED_PARAMETER_BINDABLE)
            return pev_invalid(68u, implementation, atom);
        if (!owned_constraint_binding<CatalogImplementationPatternGraph, SolverProofTermGraph>(
            state, domain == 1u, index, request))
            return state.status.state == OWNED_CONSTRAINT_MATCHED
                ? pev_invalid(68u, implementation, PEV_INVALID)
                : pev_owned_constraint_status(state.status, implementation);
        uint first_node = 0u;
        if (request.target_count != 0u)
        {
            status = pps_reserve(PPS_TERM_NODES, request.target_count, atom, first_node);
            if (status.state != PEV_VALID) return status;
        }
        uint4 allocation = uint4(first_node, request.target_count, 0u, 0u);
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

public EvidenceStatus pps_select_work(uint work)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source)) return pev_invalid(1u, work, PPS_WORK);
    if (key.z == PPS_WORK_ALIAS) return pev_ok();
    if (key.z != PPS_WORK_NEW || key.w != work) return pev_invalid(70u, work, key.z);
    uint implementation = PEV_INVALID; OwnedConstraintState state;
    EvidenceStatus status = pev_ok();
    // Keep one matcher call site while preserving exact implementation,
    // caller assumption, then generic implementation selection priority.
    [loop]
    for (uint phase = 0u; phase < 2u; phase++)
    {
        status = pps_find_implementation(key.y, phase != 0u, implementation, state);
        if (status.state != PEV_VALID) return status;
        if (implementation != PEV_INVALID || phase != 0u) break;
        uint assumption;
        status = pps_find_assumption(key.x, key.y, assumption);
        if (status.state != PEV_VALID) return status;
        if (assumption != PEV_INVALID)
        {
            key.z = PPS_WORK_READY;
            selected = uint4(PEV_INVALID, assumption, 0u, 0u);
            if (!pps_work_write(work, key, selected, completion, source)) return pev_invalid(1u, work, PPS_WORK);
            return pps_enqueue(work, PPS_EVENT_READY);
        }
    }
    if (implementation == PEV_INVALID)
    {
        key.z = PPS_WORK_MISSING;
        if (!pps_write4(PPS_WORK, work, 0u, key)) return pev_invalid(1u, work, PPS_WORK);
        return pps_enqueue(work, PPS_EVENT_FAILED);
    }
    uint substitution;
    status = pps_write_substitution(implementation, key.y, key.x, state, substitution);
    if (status.state != PEV_VALID) return status;
    key.z = PPS_WORK_SELECTED; selected = uint4(implementation, substitution, 0u, 0u);
    return pps_work_write(work, key, selected, completion, source) ? pev_ok() : pev_invalid(1u, work, PPS_WORK);
}
