// Solver-only matching connects the admitted catalog pattern graph to the
// retained proof-term graph. Catalog admission must not acquire proof resources.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.owned_implementation_graph;
import type_checker.trait_solver.proof_term_graph;
import type_checker.trait_solver.proof_store_abi;
import type_checker.owned_type_constraint_contract;
import type_checker.owned_type_constraint_engine;

// Goal8: trait atom, subject tag/payload, argument Root2 span(first,count),
// structural hash, closed flag, reserved. Context belongs to Work/Proof, not to
// the semantic goal; work memoization keys must additionally include Context13.
public bool pps_goal_root(uint goal, uint ordinal, out uint2 reference)
{
    reference = uint2(0u, TS_INVALID); uint4 low; uint4 high;
    if (!pps_read8(PPS_GOALS, goal, low, high) || high.x > 32u || high.z > 1u || high.w != 0u ||
        ordinal > high.x) return false;
    if (ordinal == 0u) { reference = low.yz; return pps_type_reference(reference); }
    return pps_span(PPS_TERM_ROOTS, low.w, high.x) &&
        pps_read2(PPS_TERM_ROOTS, low.w + ordinal - 1u, 0u, reference);
}
// One root sequence to unify against a goal's roots: an implementation head
// (head = true: catalog row 9, inferring bindings before finish) or a fixed
// prerequisite predicate (head = false: catalog row 8, rechecked against the
// finished head state). Roots are first_root, then `arguments` argument roots
// starting at row argument_root of table 7.
public struct TsRootMatch
{
    public uint subject;
    public uint goal;
    public uint first_root;
    public uint argument_root;
    public uint arguments;
    public bool head;
}

// Unifies every root of `match` through one call site, so a kernel that runs
// both a head match and fixed prerequisite checks (implementation proof
// admission) expands the unification once. The result is in state.status:
// MATCHED or the first failure. A root that cannot be read is invalid.
public EvidenceStatus ts_match_roots(TsRootMatch match, inout OwnedConstraintState state)
{
    [loop]
    for (uint i = 0u; i <= match.arguments; i++)
    {
        // A head match stops before reading the roots after a failure, also
        // one from owned_constraints_begin.
        if (match.head && state.status.state != OWNED_CONSTRAINT_MATCHED) break;
        // A head re-derives ts_implementation_root's arity and span checks.
        bool rows = !match.head || (match.arguments <= 32u &&
            (i == 0u || ts_row_span(7u, match.argument_root, match.arguments)));
        uint2 left; uint2 right;
        if (!rows || !ts_read_root(i == 0u ? match.first_root : match.argument_root + i - 1u, left) ||
            !pps_goal_root(match.goal, i, right))
            return ts_invalid(1u, match.subject, match.goal);
        if (owned_constraints_match_or_fixed<CatalogImplementationPatternGraph, SolverProofTermGraph>(
            left, right, !match.head, state).state != OWNED_CONSTRAINT_MATCHED) break;
    }
    return ts_ok();
}

// The match state uses owned constraint frame `frame` (owned_constraint_frame).
// A head whose trait or argument count differs from the goal's is no
// candidate (and leaves the state zero); a candidate's state has begun.
public EvidenceStatus ts_begin_implementation_goal(uint implementation, uint goal,
    OwnedConstraintLimits limits, uint frame, out OwnedConstraintState state,
    out TsRootMatch match, out bool candidate)
{
    state = (OwnedConstraintState)0; candidate = false;
    uint4 pattern; uint4 args; uint4 actual; uint4 extra; uint pattern_nodes; uint goal_nodes; uint atoms;
    bool read = ts_read4(9u, implementation, 0u, pattern) && ts_read4(9u, implementation, 4u, args) &&
        pps_read8(PPS_GOALS, goal, actual, extra) &&
        ts_catalog_count(5u, pattern_nodes) && pps_count(PPS_TERM_NODES, goal_nodes) &&
        ts_table_count(1u, atoms);
    match = { implementation, goal, pattern.w, args.x, args.y, true };
    if (!read) return ts_invalid(1u, implementation, goal);
    if (pattern.z != actual.x || args.y != extra.x) return ts_ok();
    candidate = true;
    owned_constraints_begin<CatalogImplementationPatternGraph>(
        pattern.y, pattern_nodes, goal_nodes, atoms, limits, frame, state);
    return ts_ok();
}

// After ts_match_roots of a head: NoMatch is no match, a match must finish.
public EvidenceStatus ts_finish_implementation_goal(uint implementation,
    inout OwnedConstraintState state, out bool matches)
{
    matches = false;
    if (state.status.state == OWNED_CONSTRAINT_NO_MATCH) return ts_ok();
    if (state.status.state == OWNED_CONSTRAINT_MATCHED)
        owned_constraints_finish<CatalogImplementationPatternGraph, SolverProofTermGraph>(state);
    if (state.status.state != OWNED_CONSTRAINT_MATCHED)
        return ts_owned_constraint_status(state.status, implementation);
    matches = true; return ts_ok();
}

public EvidenceStatus ts_match_implementation_goal(uint implementation, uint goal,
    OwnedConstraintLimits limits, uint frame, out bool matches, out OwnedConstraintState state)
{
    matches = false;
    TsRootMatch match; bool candidate;
    EvidenceStatus status = ts_begin_implementation_goal(implementation, goal, limits, frame,
        state, match, candidate);
    if (status.state != TS_VALID || !candidate) return status;
    status = ts_match_roots(match, state);
    if (status.state != TS_VALID) return status;
    return ts_finish_implementation_goal(implementation, state, matches);
}
