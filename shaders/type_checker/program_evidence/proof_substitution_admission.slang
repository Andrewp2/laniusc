// Admit one substitution together with its complete owned binding span. Only
// their declared projection-node spans may be pending. The conclusion goal
// and exact request leaves remain admitted-only. This validator reads frozen rows and publishes no
// count, proof, or substitution authority on its own.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.program_evidence.proof_goal_admission;
import type_checker.program_evidence.proof_binding_materialization;
import type_checker.program_evidence.proof_term_candidate;
import type_checker.program_evidence.owned_implementation_graph;
import type_checker.program_evidence.implementation_goal_matching;
import type_checker.owned_type_constraint_contract;
import type_checker.owned_type_constraint_engine;
import type_checker.scoped_type_equality;

// Substitution4: implementation, first Binding, count, conclusion Goal.
// Binding8: substitution backlink, exact parameter atom, term tag/payload;
// owned projection-node span(first,count), two reserved zero words.
// Complete layout admission and the emission barrier precede this call. The
// caller advances node, substitution and binding prefixes only after the whole
// wave succeeds, including independent allocation coverage.
public EvidenceStatus pps_admit_substitution(uint substitution, uint context,
    OwnedConstraintLimits limits, out OwnedConstraintState match_state,
    out bool concrete)
{
    match_state = (OwnedConstraintState)0;
    match_state.status = owned_constraint_invalid(3u);
    concrete = false;
    uint4 substitutions; uint4 bindings; uint accepted;
    if (!pps_building() || !pps_descriptor(PPS_SUBSTITUTIONS, substitutions, accepted) ||
        !pps_descriptor(PPS_BINDINGS, bindings, accepted) || substitution >= substitutions.y)
        return pev_invalid(68u, substitution, PEV_INVALID);

    uint4 row;
    bool read = substitution < substitutions.w
        ? pps_read4(PPS_SUBSTITUTIONS, substitution, 0u, row)
        : pps_read_pending4(PPS_SUBSTITUTIONS, substitution, 0u, row);
    if (!read || row.z > 64u || (row.z == 0u && row.y != 0u) ||
        row.y > bindings.y || row.z > bindings.y - row.y)
        return pev_invalid(68u, substitution, PEV_INVALID);

    // The goal-stage helper can inspect its own pending row. This consumer
    // must first prove that its referenced goal has already been admitted.
    uint goals; bool conclusion_closed;
    if (!pps_count(PPS_GOALS, goals) || row.w >= goals)
        return pev_invalid(68u, substitution, row.w);
    EvidenceStatus status = pps_admit_goal(row.w, context, conclusion_closed);
    if (status.state != PEV_VALID) return status;

    bool matches; OwnedConstraintState inferred;
    status = pev_match_implementation_goal(row.x, row.w, limits, matches, inferred);
    if (status.state != PEV_VALID) return status;
    if (!matches || row.z != inferred.counts.x + inferred.counts.y)
        return pev_invalid(68u, substitution, row.x);

    uint nodes; uint atoms; uint owner; bool require_closed;
    if (!pps_count(PPS_TERM_NODES, nodes) || !pev_table_count(1u, atoms) ||
        !pev_context_goal_scope(context, owner, require_closed))
        return pev_invalid(1u, substitution, context);
    uint previous = PEV_INVALID;
    uint2 covered = uint2(0u, 0u);
    bool all_closed = conclusion_closed;
    [loop]
    for (uint i = 0u; i < row.z; i++)
    {
        uint binding_row = row.y + i;
        uint4 binding; uint4 allocation; uint4 parameter;
        bool binding_read = binding_row < bindings.w
            ? pps_read8(PPS_BINDINGS, binding_row, binding, allocation)
            : pps_read_pending8(PPS_BINDINGS, binding_row, binding, allocation);
        if (!binding_read || !pps_binding_node_span(allocation, binding_row >= bindings.w) ||
            binding.x != substitution ||
            (i != 0u && binding.y <= previous) ||
            !pev_read_admitted_parameter(binding.y, parameter))
            return pev_invalid(68u, substitution, binding_row);
        previous = binding.y;

        uint index;
        uint member = CatalogImplementationPatternGraph.owned_parameter(
            inferred.owners.x, binding.y, parameter.z == 1u, index);
        OwnedConstraintBindingRequest request;
        if (member != OWNED_PARAMETER_BINDABLE || index >= 32u)
            return pev_invalid(68u, substitution, binding.y);
        if (!owned_constraint_binding<CatalogImplementationPatternGraph, SolverProofTermGraph>(
            inferred, parameter.z == 1u, index, request))
            return inferred.status.state == OWNED_CONSTRAINT_MATCHED
                ? pev_invalid(68u, substitution, PEV_INVALID)
                : pev_owned_constraint_status(inferred.status, substitution);
        uint bit = 1u << index;
        if ((covered[parameter.z] & bit) != 0u)
            return pev_invalid(68u, substitution, binding.y);
        covered[parameter.z] |= bit;

        uint2 expected; bool value_closed;
        // Reconstruct and compare every owned row, including concrete children
        // folded out of the reachable root. Only this span may still be pending.
        status = pps_materialize_binding_request<OwnedBindingCheckSink>(request, binding.y,
            owner, require_closed, allocation, expected, value_closed);
        if (status.state != PEV_VALID) return status;
        if (any(binding.zw != expected)) return pev_invalid(68u, substitution, binding.y);
        if (allocation.y != 0u)
        {
            uint2 unused; bool candidate_closed; ProofNormalizationCounts measured;
            ProofNormalizationReservation empty = (ProofNormalizationReservation)0;
            status = pev_normalize_proof_root<SameProofNormalizationGraph<CandidateProofTermGraph>,
                SolverProofBindings, SolverProofTermSink>(binding.zw, PEV_INVALID, owner,
                    PEV_ADMITTED_DOMAIN_CONSTANT, false, empty, unused, candidate_closed, measured);
            if (status.state != PEV_VALID) return status;
            if (candidate_closed != value_closed || (require_closed && !candidate_closed))
                return pev_invalid(68u, substitution, binding.y);
        }
        all_closed = all_closed && value_closed;
    }
    if (covered.x != owned_constraint_mask(inferred.counts.x) ||
        covered.y != owned_constraint_mask(inferred.counts.y))
        return pev_invalid(68u, substitution, row.x);

    // Failed row validation never exposes a successfully finished head match.
    // Successful state retains the match budgets for fixed prerequisite checks.
    match_state = inferred;
    concrete = all_closed;
    return pev_ok();
}
