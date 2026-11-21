// Solver-only matching connects the admitted catalog pattern graph to the
// retained proof-term graph. Catalog admission must not acquire proof resources.
import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.catalog.catalog_io;
import type_checker.trait_solver.owned_implementation_graph;
import type_checker.trait_solver.proof_term_graph;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.owned_type_constraint_contract;
import type_checker.trait_solver.owned_type_constraint_engine;

// The caller has read the normalized goal once. All candidates use its
// immutable roots and preserve a single constraint state across the roots.
public SolverStatus ts_match_implementation_goal(uint implementation, uint goal,
    uint4 actual, uint4 extra, OwnedConstraintLimits limits, uint frame,
    out bool matches, out OwnedConstraintState state)
{
    matches = false; state = (OwnedConstraintState)0;
    uint4 pattern; uint4 args;
    if (!ts_read4(9u, implementation, 0u, pattern) || !ts_read4(9u, implementation, 4u, args))
        return ts_invalid(1u, implementation, goal);
    if (pattern.z != actual.x || args.y != extra.x) return ts_ok();

    uint pattern_nodes; uint goal_nodes; uint atoms;
    if (!ts_catalog_count(5u, pattern_nodes) || !pps_count(PPS_TERM_NODES, goal_nodes) ||
        !ts_table_count(1u, atoms))
        return ts_invalid(1u, implementation, goal);
    owned_constraints_begin<CatalogImplementationPatternGraph>(
        pattern.y, pattern_nodes, goal_nodes, atoms, limits, frame, state);
    // The goal builder admitted the subject and wrote the complete root span.
    [loop]
    for (uint i = 0u; i <= args.y && state.status.state == OWNED_CONSTRAINT_MATCHED; i++)
    {
        uint2 left; uint2 right = actual.yz;
        if (!ts_read_root(i == 0u ? pattern.w : args.x + i - 1u, left) ||
            (i != 0u && !pps_read2(PPS_TERM_ROOTS, actual.w + i - 1u, 0u, right)))
            return ts_invalid(1u, implementation, goal);
        owned_constraints_match_or_fixed<CatalogImplementationPatternGraph, SolverProofTermGraph>(
            left, right, false, state);
    }
    if (state.status.state == OWNED_CONSTRAINT_NO_MATCH) return ts_ok();
    if (state.status.state == OWNED_CONSTRAINT_MATCHED)
        owned_constraints_finish<CatalogImplementationPatternGraph, SolverProofTermGraph>(state);
    if (state.status.state != OWNED_CONSTRAINT_MATCHED)
        return ts_owned_constraint_status(state.status, implementation);
    matches = true; return ts_ok();
}
