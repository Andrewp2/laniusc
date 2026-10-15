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
// One root sequence to unify against a goal's roots: an implementation head
// (head = true: catalog row 9, inferring bindings before finish) or a fixed
// prerequisite predicate (head = false: catalog row 8, rechecked against the
// finished head state). Roots are first_root, then `arguments` argument roots
// starting at row argument_root of table 7.
public struct PevRootMatch
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
public EvidenceStatus pev_match_roots(PevRootMatch match, inout OwnedConstraintState state)
{
    [loop]
    for (uint i = 0u; i <= match.arguments; i++)
    {
        // A head match stops before reading the roots after a failure, also
        // one from owned_constraints_begin.
        if (match.head && state.status.state != OWNED_CONSTRAINT_MATCHED) break;
        // A head re-derives pev_implementation_root's arity and span checks.
        bool rows = !match.head || (match.arguments <= 32u &&
            (i == 0u || pev_row_span(7u, match.argument_root, match.arguments)));
        uint2 left; uint2 right;
        if (!rows || !pev_read_root(i == 0u ? match.first_root : match.argument_root + i - 1u, left) ||
            !pps_goal_root(match.goal, i, right))
            return pev_invalid(1u, match.subject, match.goal);
        if (owned_constraints_match_or_fixed<CatalogImplementationPatternGraph, SolverProofTermGraph>(
            left, right, !match.head, state).state != OWNED_CONSTRAINT_MATCHED) break;
    }
    return pev_ok();
}

// The match state uses owned constraint frame `frame` (owned_constraint_frame).
// A head whose trait or argument count differs from the goal's is no
// candidate (and leaves the state zero); a candidate's state has begun.
public EvidenceStatus pev_begin_implementation_goal(uint implementation, uint goal,
    OwnedConstraintLimits limits, uint frame, out OwnedConstraintState state,
    out PevRootMatch match, out bool candidate)
{
    state = (OwnedConstraintState)0; candidate = false;
    uint4 pattern; uint4 args; uint4 actual; uint4 extra; uint pattern_nodes; uint goal_nodes; uint atoms;
    bool read = pev_read4(9u, implementation, 0u, pattern) && pev_read4(9u, implementation, 4u, args) &&
        pps_read8(PPS_GOALS, goal, actual, extra) &&
        pev_catalog_count(5u, pattern_nodes) && pps_count(PPS_TERM_NODES, goal_nodes) &&
        pev_table_count(1u, atoms);
    match = { implementation, goal, pattern.w, args.x, args.y, true };
    if (!read) return pev_invalid(1u, implementation, goal);
    if (pattern.z != actual.x || args.y != extra.x) return pev_ok();
    candidate = true;
    owned_constraints_begin<CatalogImplementationPatternGraph>(
        pattern.y, pattern_nodes, goal_nodes, atoms, limits, frame, state);
    return pev_ok();
}

// After pev_match_roots of a head: NoMatch is no match, a match must finish.
public EvidenceStatus pev_finish_implementation_goal(uint implementation,
    inout OwnedConstraintState state, out bool matches)
{
    matches = false;
    if (state.status.state == OWNED_CONSTRAINT_NO_MATCH) return pev_ok();
    if (state.status.state == OWNED_CONSTRAINT_MATCHED)
        owned_constraints_finish<CatalogImplementationPatternGraph, SolverProofTermGraph>(state);
    if (state.status.state != OWNED_CONSTRAINT_MATCHED)
        return pev_owned_constraint_status(state.status, implementation);
    matches = true; return pev_ok();
}

public EvidenceStatus pev_match_implementation_goal(uint implementation, uint goal,
    OwnedConstraintLimits limits, uint frame, out bool matches, out OwnedConstraintState state)
{
    matches = false;
    PevRootMatch match; bool candidate;
    EvidenceStatus status = pev_begin_implementation_goal(implementation, goal, limits, frame,
        state, match, candidate);
    if (status.state != PEV_VALID || !candidate) return status;
    status = pev_match_roots(match, state);
    if (status.state != PEV_VALID) return status;
    return pev_finish_implementation_goal(implementation, state, matches);
}
