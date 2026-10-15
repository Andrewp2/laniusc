// Solver-only matching connects the admitted catalog pattern graph to the
// retained proof-term graph. Catalog admission must not acquire proof resources.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.owned_implementation_graph;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_store_abi;
import type_checker.owned_type_constraint_contract;
import type_checker.owned_type_constraint_engine;

// Goal8: trait atom, subject tag/payload, argument Root2 span(first,count),
// structural hash, closed flag, reserved. Context belongs to Work/Proof, not to
// the semantic goal; work memoization keys must additionally include Context13.
public bool pps_goal_root(uint goal, uint ordinal, out uint2 reference)
{
    reference = uint2(0u, PEV_INVALID); uint4 low; uint4 high;
    if (!pps_read8(PPS_GOALS, goal, low, high) || high.x > 32u || high.z > 1u || high.w != 0u ||
        ordinal > high.x) return false;
    if (ordinal == 0u) { reference = low.yz; return pps_type_reference(reference); }
    return pps_span(PPS_TERM_ROOTS, low.w, high.x) &&
        pps_read2(PPS_TERM_ROOTS, low.w + ordinal - 1u, 0u, reference);
}
// The match state uses owned constraint frame `frame` (owned_constraint_frame).
public EvidenceStatus pev_match_implementation_goal(uint implementation, uint goal,
    OwnedConstraintLimits limits, uint frame, out bool matches, out OwnedConstraintState state)
{
    matches = false; state = (OwnedConstraintState)0;
    uint4 pattern; uint4 args; uint4 actual; uint4 extra; uint pattern_nodes; uint goal_nodes; uint atoms;
    if (!pev_read4(9u, implementation, 0u, pattern) || !pev_read4(9u, implementation, 4u, args) ||
        !pps_read8(PPS_GOALS, goal, actual, extra) ||
        !pev_catalog_count(5u, pattern_nodes) || !pps_count(PPS_TERM_NODES, goal_nodes) ||
        !pev_table_count(1u, atoms)) return pev_invalid(1u, implementation, goal);
    if (pattern.z != actual.x || args.y != extra.x) return pev_ok();
    OwnedConstraintStatus status = owned_constraints_begin<CatalogImplementationPatternGraph>(
        pattern.y, pattern_nodes, goal_nodes, atoms, limits, frame, state);
    [loop]
    for (uint i = 0u; status.state == OWNED_CONSTRAINT_MATCHED && i <= args.y; i++)
    {
        uint2 left; uint2 right;
        if (!pev_implementation_root(implementation, i, left) || !pps_goal_root(goal, i, right))
            return pev_invalid(1u, implementation, goal);
        status = owned_constraints_match<CatalogImplementationPatternGraph, SolverProofTermGraph>(left, right, state);
    }
    if (status.state == OWNED_CONSTRAINT_NO_MATCH) return pev_ok();
    if (status.state == OWNED_CONSTRAINT_MATCHED) status = owned_constraints_finish<CatalogImplementationPatternGraph, SolverProofTermGraph>(state);
    if (status.state != OWNED_CONSTRAINT_MATCHED) return pev_owned_constraint_status(status, implementation);
    matches = true; return pev_ok();
}
