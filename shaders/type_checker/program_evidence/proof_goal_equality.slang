// Cross-store comparison preserves the original input graph namespace and the
// independently admitted solver graph namespace. Hashes only reject candidates;
// every matching root still receives structural equality with exact rigid atoms.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.goal_operations;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_term_graph;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_scratch;

// A proof used by replay must belong to a prior fully accepted submission. An
// admitted row in the current unfinished frontier does not authorize replay.
public bool pps_retained_proof_reference(uint proof, uint goal, uint classification,
    out uint context)
{
    context = PEV_INVALID;
    if (!pps_identity_is_valid() || (classification != 1u && classification != 2u)) return false;
    uint accepted_serial = program_evidence_proof_store[7u];
    if (accepted_serial == 0u || accepted_serial >= proof_store_params.serial) return false;
    uint4 proofs; uint accepted_proofs; uint4 goals; uint accepted_goals;
    uint4 low; uint4 high;
    if (!pps_descriptor(PPS_PROOFS, proofs, accepted_proofs) || proof >= accepted_proofs ||
        !pps_descriptor(PPS_GOALS, goals, accepted_goals) || goal >= accepted_goals ||
        !pps_read8(PPS_PROOFS, proof, low, high) || low.y != goal || high.w != classification)
        return false;
    context = low.z;
    return true;
}

// Caller has already admitted every normalized goal/root row and the complete
// source environment. Source preflight stays here so early hash/arity mismatch
// cannot conceal a malformed source root or out-of-scope caller parameter.
public EvidenceStatus pps_predicate_equals_goal(uint predicate, uint environment,
    uint visible_owner, uint goal, bool require_closed, out bool equal)
{
    equal = false;
    EvidenceGoal required;
    if (!pev_predicate_goal(predicate, environment, visible_owner, required))
        return pev_invalid(1u, predicate, goal);
    uint required_hash;
    EvidenceStatus status = pev_admit_and_hash_goal(required, require_closed, required_hash);
    if (status.state != PEV_VALID) return status;
    uint4 low; uint4 high;
    if (!pps_read8(PPS_GOALS, goal, low, high) || high.x > 32u || high.z > 1u || high.w != 0u ||
        (high.x == 0u && low.w != 0u) || !pps_span(PPS_TERM_ROOTS, low.w, high.x))
        return pev_invalid(67u, goal, predicate);
    if (require_closed && high.z != 1u) return pev_invalid(10u, goal, predicate);
    if (required.trait_atom != low.x || required.argument_count != high.x || required_hash != high.y)
        return pev_ok();
    uint input_nodes; uint solver_nodes; uint atoms;
    if (!pev_table_count(5u, input_nodes) || !pps_count(PPS_TERM_NODES, solver_nodes) ||
        !pev_table_count(1u, atoms)) return pev_invalid(1u, predicate, goal);
    [loop]
    for (uint ordinal = 0u; ordinal <= high.x; ordinal++)
    {
        uint source_root = ordinal == 0u ? required.subject_root : required.first_argument + ordinal - 1u;
        uint2 source; uint2 normalized = low.yz;
        if (!pev_read_root(source_root, source) || (ordinal != 0u &&
            !pps_read2(PPS_TERM_ROOTS, low.w + ordinal - 1u, 0u, normalized)))
            return pev_invalid(1u, predicate, goal);
        if (!scoped_type_refs_equal_graphs_scratch<ProgramEvidenceTypeGraph, SolverProofTermGraph>(
            source.x, source.y, environment, normalized.x, normalized.y, PEV_INVALID,
            input_nodes, solver_nodes, atoms)) return pev_ok();
    }
    equal = true;
    return pev_ok();
}
