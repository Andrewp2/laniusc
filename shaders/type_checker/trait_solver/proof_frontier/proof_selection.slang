// Selection of one Work's proof: the exact implementation, then a caller
// assumption, then the generic implementation. Resolution materializes the
// proof and substitution directly from the lane's matched constraint state.
import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.catalog.catalog_io;
import type_checker.trait_solver.catalog.catalog_index;
import type_checker.trait_solver.batches.batch_io;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_frontier.proof_work;
import type_checker.trait_solver.proof_goal_equality;
import type_checker.trait_solver.owned_implementation_graph;
import type_checker.trait_solver.proof_frontier.implementation_goal_matching;
import type_checker.trait_solver.proof_frontier.proof_binding_materialization;
import type_checker.trait_solver.proof_term_graph;
import type_checker.trait_solver.owned_type_constraint_contract;
import type_checker.trait_solver.owned_type_constraint_engine;
import type_checker.scoped_types.scoped_type_hash;

public OwnedConstraintLimits pps_matching_limits()
{
    OwnedConstraintLimits limits;
    limits.depth = TS_DEPTH_LIMIT; limits.pair_visits = TS_VISIT_LIMIT;
    limits.occurs_visits = TS_VISIT_LIMIT; limits.substitution_steps = TS_VISIT_LIMIT;
    return limits;
}

// The coherent catalog admits at most one matching implementation. Complete
// every bounded chain anyway: malformed links and exhausted work are errors.
public SolverStatus pps_find_implementation(uint goal, uint4 low, uint4 high, bool coarse,
    out uint selected, out OwnedConstraintState selected_state)
{
    selected = TS_INVALID; selected_state = (OwnedConstraintState)0;
    uint implementations; uint directory; uint catalog_atoms; uint batch_atoms; uint buckets;
    uint candidate; uint table = coarse ? 11u : 6u;
    if (!ts_catalog_count(9u, implementations) ||
        !ts_input_table_rows(1u, directory, catalog_atoms, batch_atoms) ||
        !ts_bucket_count(max(implementations, catalog_atoms), buckets))
        return ts_invalid(1u, goal, table);
    uint hash = coarse ? ts_coarse_implementation_hash(low.x, high.x) : high.y;
    if (!ts_output_read(coarse ? 12u : 7u, hash & (buckets - 1u), 0u, candidate))
        return ts_invalid(1u, goal, table);
    uint shape = 0u;
    uint nodes;
    if (coarse && candidate != TS_INVALID && high.x <= 32u && high.z <= 1u && high.w == 0u &&
        pps_count(PPS_TERM_NODES, nodes))
        shape = ts_self_shape<SolverProofTermGraph>(low.yz, nodes, catalog_atoms + batch_atoms);

    // The directory is fixed throughout the chain. Check it once before
    // using the bounded links in the catalog arena.
    SolverOutputTable index;
    bool described = candidate == TS_INVALID || ts_output_descriptor(table, index);
    [loop]
    for (uint examined = 0u; candidate != TS_INVALID; examined++)
    {
        if (examined == TS_CHAIN_LIMIT) return ts_limit(8u, goal, examined + 1u, TS_CHAIN_LIMIT);
        if (!described || candidate >= implementations || candidate >= index.count)
            return ts_invalid(70u, goal, candidate);
        uint address = index.offset + candidate * 4u;
        uint4 link = uint4(trait_solver_catalog[address], trait_solver_catalog[address + 1u],
            trait_solver_catalog[address + 2u], trait_solver_catalog[address + 3u]);
        if (link.z != candidate || (coarse ? (link.w & 1u) == 0u : link.w != 1u))
            return ts_invalid(70u, goal, candidate);
        uint candidate_shape = link.w >> 1u;
        if (link.x == hash && (shape == 0u || candidate_shape == 0u || shape == candidate_shape))
        {
            // A candidate never matches into the frame the selected state holds.
            bool matches; OwnedConstraintState current;
            uint frame = owned_constraint_frame(
                selected != TS_INVALID && selected_state.frame == owned_constraint_frame(0u) ? 1u : 0u);
            SolverStatus status = ts_match_implementation_goal(candidate, goal, low, high,
                pps_matching_limits(), frame, matches, current);
            if (status.state != TS_VALID) return status;
            if (matches)
            {
                if (selected != TS_INVALID && selected != candidate)
                {
                    SolverStatus conflict = ts_invalid(0u, selected, candidate);
                    conflict.state = TS_COHERENCE_CONFLICT; return conflict;
                }
                selected = candidate; selected_state = current;
            }
        }
        candidate = link.y;
    }
    return ts_ok();
}
public SolverStatus pps_find_assumption(uint context, uint goal, out uint selected)
{
    selected = TS_INVALID;
    uint4 low; uint4 high; uint assumptions; uint buckets; uint candidate;
    uint owner; bool closed;
    if (!pps_read8(PPS_GOALS, goal, low, high) || !ts_table_count(14u, assumptions) ||
        !ts_bucket_count(assumptions, buckets) || !ts_context_goal_scope(context, owner, closed))
        return ts_invalid(1u, goal, context);
    uint hash = scoped_type_hash_mix(high.y, context);
    if (!ts_output_read(9u, hash & (buckets - 1u), 0u, candidate))
        return ts_invalid(1u, goal, context);
    uint best_atom = TS_INVALID;
    [loop]
    for (uint examined = 0u; candidate != TS_INVALID; examined++)
    {
        if (examined == TS_CHAIN_LIMIT) return ts_limit(8u, goal, examined + 1u, TS_CHAIN_LIMIT);
        uint4 index; uint4 row;
        if (candidate >= assumptions || !ts_output_read4(8u, candidate, 0u, index) ||
            index.z != candidate || index.w != 1u || !ts_read4(14u, candidate, 0u, row))
            return ts_invalid(70u, goal, candidate);
        if (index.x == high.y && row.x == context)
        {
            bool equal;
            SolverStatus status = pps_assumption_equals_goal(candidate, row.y, row.z, owner, goal,
                closed, equal);
            if (status.state != TS_VALID) return status;
            if (equal)
            {
                uint atom;
                if (!ts_word(8u, row.y, 0u, atom)) return ts_invalid(1u, goal, row.y);
                if (selected == TS_INVALID || atom < best_atom)
                { selected = candidate; best_atom = atom; }
            }
        }
        candidate = index.y;
    }
    return ts_ok();
}

public SolverStatus pps_write_substitution(uint implementation, uint goal, uint context,
    inout OwnedConstraintState state, out uint substitution)
{
    substitution = TS_INVALID; uint4 head;
    uint4 span;
    if (!ts_read4(9u, implementation, 0u, head) ||
        !ts_read4(2u, head.y, 4u, span) || span.y != state.counts.x + state.counts.y || span.y > 64u)
        return ts_invalid(68u, implementation, goal);
    uint visible_owner; bool require_closed;
    if (!ts_context_goal_scope(context, visible_owner, require_closed))
        return ts_invalid(68u, implementation, context);
    uint bindings = 0u;
    uint previous = TS_INVALID;
    // Unit 0 reserves the substitution row, unit 1 the binding span, and unit
    // 2 + i writes binding i after reserving its nodes: one reservation site.
    [loop]
    for (uint unit = 0u; unit < span.y + 2u; unit++)
    {
        uint table = unit == 0u ? PPS_SUBSTITUTIONS : PPS_BINDINGS;
        uint count = unit == 0u ? 1u : span.y; uint subject = implementation;
        uint i = unit - 2u;
        uint atom = TS_INVALID; uint domain = TS_INVALID;
        OwnedConstraintBindingRequest request = (OwnedConstraintBindingRequest)0;
        if (unit >= 2u)
        {
            [loop]
            for (uint j = 0u; j < span.y; j++)
            {
                uint4 parameter;
                if (!ts_read4(3u, span.x + j, 0u, parameter) || parameter.x != head.y || parameter.w > 1u)
                    return ts_invalid(68u, implementation, span.x + j);
                if ((i == 0u || parameter.y > previous) && parameter.y < atom)
                { atom = parameter.y; domain = parameter.w; }
            }
            uint index;
            if (atom == TS_INVALID || CatalogImplementationPatternGraph.owned_parameter(
                head.y, atom, domain == 1u, index) != OWNED_PARAMETER_BINDABLE)
                return ts_invalid(68u, implementation, atom);
            if (!owned_constraint_binding<CatalogImplementationPatternGraph, SolverProofTermGraph>(
                state, domain == 1u, index, request))
                return state.status.state == OWNED_CONSTRAINT_MATCHED
                    ? ts_invalid(68u, implementation, TS_INVALID)
                    : ts_owned_constraint_status(state.status, implementation);
            table = PPS_TERM_NODES; count = request.target_count; subject = atom;
        }
        SolverStatus status;
        uint first = 0u;
        if (unit < 2u || count != 0u)
        {
            status = pps_reserve(table, count, subject, first);
            if (status.state != TS_VALID) return status;
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
        if (status.state != TS_VALID) return status;
        if (!pps_write8(PPS_BINDINGS, bindings + i,
            uint4(substitution, atom, value.x, value.y), allocation))
            return ts_invalid(68u, implementation, atom);
        previous = atom;
    }
    return pps_write4(PPS_SUBSTITUTIONS, substitution, 0u,
        uint4(implementation, bindings, span.y, goal)) ? ts_ok() : ts_invalid(1u, substitution, implementation);
}

// A goal equal to the goal of one of its ancestors has no finite proof.
// Otherwise the caller assumption of the goal, if any, is recorded.
public SolverStatus pps_select_assumption(uint work)
{
    uint4 key; uint4 link;
    if (!pps_read4(PPS_WORK, work, 0u, key) || !pps_read4(PPS_WORK, work, 4u, link))
        return ts_invalid(1u, work, PPS_WORK);
    if (key.z != PPS_WORK_BUILT) return ts_ok();
    uint ancestor = key.w;
    [loop]
    for (uint depth = 0u; ancestor != TS_INVALID; depth++)
    {
        uint4 other;
        if (depth > TS_DEPTH_LIMIT) return ts_limit(6u, work, depth + 1u, TS_DEPTH_LIMIT);
        if (!pps_read4(PPS_WORK, ancestor, 0u, other) || other.z != PPS_WORK_PROVEN)
            return ts_invalid(70u, work, ancestor);
        if (pps_goal_equal(key.y, other.y))
            return pps_refute_work(work, key.w, link.x, PPS_VERDICT_CYCLE);
        ancestor = other.w;
    }
    uint assumption;
    SolverStatus status = pps_find_assumption(key.x, key.y, assumption);
    if (status.state != TS_VALID) return status;
    return pps_write_word(PPS_WORK, work, PPS_WORK_ASSUMPTION, assumption) ? ts_ok() :
        ts_invalid(1u, work, PPS_WORK);
}

// Select a proof, then write its substitution and one child Work per
// prerequisite. Each child writes its proof into its parent's ProofEdge.
public SolverStatus pps_resolve_work(uint work)
{
    uint4 key; uint4 link; uint4 result; uint4 extra;
    if (!pps_read4(PPS_WORK, work, 0u, key) || !pps_read4(PPS_WORK, work, 4u, link) ||
        !pps_read4(PPS_WORK, work, 8u, result) || !pps_read4(PPS_WORK, work, 12u, extra))
        return ts_invalid(1u, work, PPS_WORK);
    if (key.z != PPS_WORK_BUILT) return ts_ok();
    uint4 goal; uint4 goal_extra;
    if (!pps_read8(PPS_GOALS, key.y, goal, goal_extra)) return ts_invalid(1u, work, key.y);
    uint implementation = TS_INVALID; uint assumption = extra.x;
    OwnedConstraintState state = (OwnedConstraintState)0;
    [loop]
    for (uint pass = 0u; pass < 2u; pass++)
    {
        if (pass == 1u && (implementation != TS_INVALID || assumption != TS_INVALID)) break;
        SolverStatus status = pps_find_implementation(key.y, goal, goal_extra, pass == 1u,
            implementation, state);
        if (status.state != TS_VALID) return status;
    }
    if (!pps_write_word(PPS_WORK, work, PPS_WORK_IMPLEMENTATION, implementation))
        return ts_invalid(1u, work, PPS_WORK);
    if (implementation == TS_INVALID && assumption == TS_INVALID)
        return pps_refute_work(work, key.w, link.x, PPS_VERDICT_MISSING);
    uint4 context_extra;
    if (!ts_read4(13u, key.x, 4u, context_extra))
        return ts_invalid(1u, work, key.y);
    uint kind = 2u; uint source = assumption; uint substitution = TS_INVALID;
    uint4 prerequisites = uint4(0u);
    bool closed = context_extra.y == 1u;
    if (implementation != TS_INVALID)
    {
        SolverStatus written = pps_write_substitution(implementation, key.y, key.x, state, substitution);
        if (written.state != TS_VALID) return written;
        if (!ts_read4(9u, implementation, 8u, prerequisites) || prerequisites.z != 0u ||
            prerequisites.w != 0u || !ts_row_span(8u, prerequisites.x, prerequisites.y))
            return ts_invalid(68u, work, implementation);
        kind = 1u; source = implementation; closed = goal_extra.z == 1u;
    }
    else
    {
        uint4 row;
        if (!ts_read4(14u, assumption, 0u, row) || row.x != key.x)
            return ts_invalid(68u, work, assumption);
    }
    uint children = prerequisites.y;
    if (children != 0u && result.z + 1u >= TS_DEPTH_LIMIT)
        return ts_limit(6u, work, result.z + 2u, TS_DEPTH_LIMIT);
    uint3 first = uint3(0u);
    [loop]
    for (uint unit = 0u; unit < 3u; unit++)
    {
        uint reserved;
        SolverStatus status = pps_reserve(unit == 0u ? PPS_PROOFS : (unit == 1u ? PPS_PROOF_EDGES : PPS_WORK),
            unit == 0u ? 1u : children, work, reserved);
        if (status.state != TS_VALID) return status;
        first[unit] = reserved;
    }
    uint proof = first.x;
    if (!pps_write8(PPS_PROOFS, proof, uint4(kind, key.y, key.x, source),
        uint4(substitution, first.y, children, closed ? PPS_PROOF_CLOSED : PPS_PROOF_CONDITIONAL)))
        return ts_invalid(1u, work, proof);
    [loop]
    for (uint i = 0u; i < children; i++)
    {
        uint child = first.z + i; uint edge = first.y + i; uint predicate = prerequisites.x + i;
        if (!pps_write4(PPS_PROOF_EDGES, edge, 0u, uint4(proof, predicate, TS_INVALID, 0u)) ||
            !pps_write4(PPS_WORK, child, 0u, uint4(key.x, TS_INVALID, PPS_WORK_PENDING, work)) ||
            !pps_write4(PPS_WORK, child, 4u, uint4(link.x, predicate, substitution, edge)) ||
            !pps_write4(PPS_WORK, child, 8u, uint4(TS_INVALID, TS_INVALID, result.z + 1u, 0u)) ||
            !pps_write4(PPS_WORK, child, 12u, uint4(TS_INVALID, TS_INVALID, 0u, 0u)))
            return ts_invalid(1u, work, child);
    }
    if (link.w != TS_INVALID && !pps_write_word(PPS_PROOF_EDGES, link.w, 2u, proof))
        return ts_invalid(1u, work, link.w);
    if (!pps_write_word(PPS_WORK, work, PPS_WORK_PROOF, proof) ||
        !pps_write_word(PPS_WORK, work, PPS_WORK_STATE, PPS_WORK_PROVEN))
        return ts_invalid(1u, work, proof);
    return closed ? ts_ok() : pps_raise_ancestor_proofs(work, key.w, PPS_PROOF_CONDITIONAL);
}

// The result of source obligation `obligation`, whose root is Work `work`.
// A tree with a missing proof is refuted with detail 0, and a tree whose
// only failures are cycles with detail 71.
public SolverStatus pps_publish_root(uint obligation, uint work)
{
    uint4 key; uint4 link; uint4 result; uint4 extra; uint4 source;
    if (!pps_read4(PPS_WORK, work, 0u, key) || !pps_read4(PPS_WORK, work, 4u, link) ||
        !pps_read4(PPS_WORK, work, 8u, result) || !pps_read4(PPS_WORK, work, 12u, extra) ||
        key.w != TS_INVALID || link.x != work || extra.y != obligation ||
        !ts_read4(16u, obligation, 0u, source))
        return ts_invalid(70u, obligation, work);
    if (result.w != 0u || key.z == PPS_WORK_REFUTED)
    {
        ts_obligation_status(obligation, 3u, result.w == PPS_VERDICT_CYCLE ? 71u : 0u, TS_INVALID,
            result.y, TS_INVALID, 0u, 0u);
        return ts_ok();
    }
    uint4 proof; uint4 high;
    if (key.z != PPS_WORK_PROVEN || !pps_read8(PPS_PROOFS, result.x, proof, high) ||
        proof.y != key.y || proof.z != key.x ||
        (high.w != PPS_PROOF_CLOSED && high.w != PPS_PROOF_CONDITIONAL))
        return ts_invalid(70u, obligation, work);
    if (!ts_output_evidence(obligation, uint4(high.w, source.y, source.z, result.x),
        uint4(key.y, source.x, obligation, 0u))) return ts_invalid(1u, obligation, 5u);
    ts_obligation_proven(obligation, high.w, result.x, proof.x, proof.w);
    return ts_ok();
}
