// Cross-store comparison preserves the original input graph namespace and the
// independently admitted solver graph namespace. Hashes only reject candidates;
// every matching root still receives structural equality with exact rigid atoms.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.packed_graph;
import type_checker.trait_solver.goal_operations;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_term_graph;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_scratch;

// A proof used by replay must belong to a prior fully accepted submission. An
// admitted row in the current unfinished frontier does not authorize replay.
public bool pps_retained_proof_reference(uint proof, uint goal, uint classification,
    out uint context)
{
    context = TS_INVALID;
    if (!pps_identity_is_valid() || (classification != 1u && classification != 2u)) return false;
    uint accepted_serial = trait_solver_proof_store[7u];
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
public SolverStatus pps_predicate_equals_goal(uint predicate, uint environment,
    uint visible_owner, uint goal, bool require_closed, out bool equal)
{
    equal = false;
    SolverGoal required;
    if (!ts_predicate_goal(predicate, environment, visible_owner, required))
        return ts_invalid(1u, predicate, goal);
    uint required_hash;
    SolverStatus status = ts_admit_and_hash_goal(required, require_closed, required_hash);
    if (status.state != TS_VALID) return status;
    return pps_required_equals_goal(predicate, environment, required, required_hash, goal,
        require_closed, equal);
}
// A caller assumption's predicate (input table 14 row `assumption`) against a
// goal. Kernel 15 admitted and hashed this predicate in the same scope and
// closure into the assumption index row, and an indexed row never changes for
// the rest of the batch lifecycle (see
// docs/compiler-implementation-evidence-plan.md, "Program graph and context
// contracts"), so the index hash stands in for a second admission.
public SolverStatus pps_assumption_equals_goal(uint assumption, uint predicate,
    uint environment, uint visible_owner, uint goal, bool require_closed, out bool equal)
{
    equal = false;
    SolverGoal required; uint4 index;
    if (!ts_predicate_goal(predicate, environment, visible_owner, required))
        return ts_invalid(1u, predicate, goal);
    if (!ts_output_read4(8u, assumption, 0u, index) || index.z != assumption || index.w != 1u)
        return ts_invalid(70u, goal, assumption);
    return pps_required_equals_goal(predicate, environment, required, index.x, goal,
        require_closed, equal);
}
SolverStatus pps_required_equals_goal(uint predicate, uint environment, SolverGoal required,
    uint required_hash, uint goal, bool require_closed, out bool equal)
{
    equal = false;
    uint4 low; uint4 high;
    if (!pps_read8(PPS_GOALS, goal, low, high) || high.x > 32u || high.z > 1u || high.w != 0u ||
        (high.x == 0u && low.w != 0u) || !pps_span(PPS_TERM_ROOTS, low.w, high.x))
        return ts_invalid(67u, goal, predicate);
    if (require_closed && high.z != 1u) return ts_invalid(10u, goal, predicate);
    if (required.trait_atom != low.x || required.argument_count != high.x || required_hash != high.y)
        return ts_ok();
    uint input_nodes; uint solver_nodes; uint atoms;
    if (!ts_table_count(5u, input_nodes) || !pps_count(PPS_TERM_NODES, solver_nodes) ||
        !ts_table_count(1u, atoms)) return ts_invalid(1u, predicate, goal);
    [loop]
    for (uint ordinal = 0u; ordinal <= high.x; ordinal++)
    {
        uint source_root = ordinal == 0u ? required.subject_root : required.first_argument + ordinal - 1u;
        uint2 source; uint2 normalized = low.yz;
        if (!ts_read_root(source_root, source) || (ordinal != 0u &&
            !pps_read2(PPS_TERM_ROOTS, low.w + ordinal - 1u, 0u, normalized)))
            return ts_invalid(1u, predicate, goal);
        if (!scoped_type_refs_equal_graphs_scratch<TraitSolverTypeGraph, SolverProofTermGraph>(
            source.x, source.y, environment, normalized.x, normalized.y, TS_INVALID,
            input_nodes, solver_nodes, atoms)) return ts_ok();
    }
    equal = true;
    return ts_ok();
}
