// Admission is a complete graph validation and work bound, not a second solver.
import type_checker.trait_solver.catalog_admission.graph_admission;
import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.packed_graph;
import type_checker.scoped_types.scoped_type_equality;
import type_checker.scoped_types.scoped_type_hash;
import type_checker.trait_solver.scoped_type_scratch;

public SolverStatus ts_admit_environment(
    uint environment, uint expected_owner, uint caller_owner, uint form, out bool closed)
{
    closed = true;
    SolverStatus status = ts_admit_environment_header(environment, expected_owner, form);
    if (status.state != TS_VALID) return status;
    uint4 env;
    if (!ts_environment_header(environment, env)) return ts_invalid(1u, environment, TS_INVALID);
    for (uint index = 0u; index < env.z; index++)
    {
        uint root;
        if (!ts_word(12u, env.y + index, 2u, root)) return ts_invalid(1u, environment, index);
        bool root_closed;
        // Even parameters unused by a predicate must have admitted values.
        // A concrete body environment requires closed roots; call bindings may
        // retain exact parameters of the actual caller's lexical owner chain.
        status = ts_admit_root(root, TS_INVALID, caller_owner, form == 0u, root_closed);
        if (status.state != TS_VALID) return status;
        closed = closed && root_closed;
    }
    return ts_ok();
}

// Caller must first admit each supplied environment with its exact target owner
// and caller scope. An INVALID environment is the original symbolic context.
// Each root has an independent budget; 32 operands do not share one 64-node cap.
public SolverStatus ts_hash_root(
    uint root, uint environment, uint visible_owner, bool require_closed, out uint hash)
{
    hash = 0u;
    bool root_closed;
    SolverStatus status = ts_admit_root(root, environment, visible_owner, require_closed, root_closed);
    if (status.state != TS_VALID) return status;
    uint2 reference; uint nodes; uint atoms;
    if (!ts_read_root(root, reference) || !ts_table_count(5u, nodes) || !ts_table_count(1u, atoms))
        return ts_invalid(1u, root, TS_INVALID);
    if (!scoped_type_ref_hash_scratch<TraitSolverTypeGraph>(
        reference.x, reference.y, environment, nodes, atoms, hash))
        return ts_invalid(15u, root, TS_INVALID);
    return ts_ok();
}

public SolverStatus ts_equal_roots(
    uint left_root, uint left_environment, uint left_visible_owner, bool left_closed,
    uint right_root, uint right_environment, uint right_visible_owner, bool right_closed,
    out bool equal)
{
    equal = false;
    bool root_closed;
    SolverStatus status = ts_admit_root(
        left_root, left_environment, left_visible_owner, left_closed, root_closed);
    if (status.state != TS_VALID) return status;
    status = ts_admit_root(right_root, right_environment, right_visible_owner, right_closed, root_closed);
    if (status.state != TS_VALID) return status;
    uint2 left; uint2 right; uint nodes; uint atoms;
    if (!ts_read_root(left_root, left) || !ts_read_root(right_root, right) ||
        !ts_table_count(5u, nodes) || !ts_table_count(1u, atoms))
        return ts_invalid(1u, left_root, right_root);
    equal = scoped_type_refs_equal_scratch<TraitSolverTypeGraph>(
        left.x, left.y, left_environment, right.x, right.y, right_environment, nodes, atoms);
    // Preflight proved both complete input graphs well formed, bounded and
    // fully substitutable. A false shared comparison here means valid inequality.
    return ts_ok();
}
