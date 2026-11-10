// A goal is one accepted predicate or concrete implementation, evaluated under
// its exact environment. Admission precedes candidate equality; hashing is not
// evidence. Each ordered operand has an independent graph-work budget.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.packed_graph;
import type_checker.trait_solver.checked_graph_operations;
import type_checker.trait_solver.graph_admission;
import type_checker.scoped_type_hash;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_scratch;

public struct EvidenceGoal
{
    public uint trait_atom; public uint subject_root; public uint first_argument; public uint argument_count;
    public uint environment; public uint visible_owner;
}
public bool ts_predicate_goal(uint predicate, uint environment, uint visible_owner, out EvidenceGoal goal)
{
    goal = (EvidenceGoal)0; uint4 low; uint4 high;
    if (!ts_read4(8u, predicate, 0u, low) || !ts_read4(8u, predicate, 4u, high)) return false;
    goal.trait_atom = low.z; goal.subject_root = low.w;
    goal.first_argument = high.x; goal.argument_count = high.y;
    goal.environment = environment; goal.visible_owner = visible_owner; return true;
}
public bool ts_implementation_goal(uint implementation, out EvidenceGoal goal)
{
    goal = (EvidenceGoal)0; uint4 low; uint4 middle;
    if (!ts_read4(9u, implementation, 0u, low) || !ts_read4(9u, implementation, 4u, middle)) return false;
    goal.trait_atom = low.z; goal.subject_root = low.w;
    goal.first_argument = middle.x; goal.argument_count = middle.y;
    goal.environment = TS_INVALID; goal.visible_owner = low.y; return true;
}
public EvidenceStatus ts_admit_and_hash_goal(EvidenceGoal goal, bool closed, out uint hash)
{
    hash = 0u;
    if (!ts_nominal_is_valid(goal.trait_atom)) return ts_invalid(2u, goal.trait_atom, TS_INVALID);
    if (goal.argument_count > 32u) return ts_limit(19u, goal.subject_root, goal.argument_count, 32u);
    if ((goal.argument_count == 0u && goal.first_argument != 0u) ||
        !ts_row_span(7u, goal.first_argument, goal.argument_count))
        return ts_invalid(1u, goal.subject_root, goal.first_argument);
    // Goal operations run after every required suffix row stage. Root shape
    // uses admitted atoms; the full contextual preflight below is still required.
    uint2 subject;
    if (!ts_read_root(goal.subject_root, subject) || !ts_admitted_type_reference_shape(subject))
        return ts_invalid(4u, goal.subject_root, TS_INVALID);
    uint accumulated = scoped_type_hash_mix(2166136261u, goal.trait_atom);
    accumulated = scoped_type_hash_mix(accumulated, goal.argument_count);
    // A goal's ordered roots are subject, then operands. Use one traversal
    // call site: duplicating it for the subject expands the complete checked
    // graph walker again in drivers that inline SPIR-V functions.
    [loop]
    for (uint i = 0u; i <= goal.argument_count; i++)
    {
        uint root = goal.subject_root;
        if (i != 0u) root = goal.first_argument + (i - 1u);
        uint child_hash;
        EvidenceStatus status = ts_hash_root(root, goal.environment,
            goal.visible_owner, closed, child_hash);
        if (status.state != TS_VALID) return status;
        accumulated = scoped_type_hash_mix(accumulated, child_hash);
    }
    hash = accumulated;
    return ts_ok();
}
public bool ts_equal_admitted_goal_roots(uint left_root, uint left_env, uint right_root, uint right_env)
{
    uint2 left; uint2 right; uint nodes; uint atoms;
    if (!ts_read_root(left_root, left) || !ts_read_root(right_root, right) ||
        !ts_table_count(5u, nodes) || !ts_table_count(1u, atoms)) return false;
    return scoped_type_refs_equal_scratch<TraitSolverTypeGraph>(
        left.x, left.y, left_env, right.x, right.y, right_env, nodes, atoms);
}
public bool ts_equal_admitted_goals(EvidenceGoal left, EvidenceGoal right)
{
    // Only called after complete goal and complete environment admission.
    // Inputs stay immutable through every equality dispatch. Thus shared false
    // is valid inequality, rather than a short-circuit admission result.
    if (left.trait_atom != right.trait_atom || left.argument_count != right.argument_count ||
        left.argument_count > 32u) return false;
    // Keep subject-first order and a separate traversal budget for each root,
    // while sharing the same comparison call site across all ordered roots.
    [loop]
    for (uint i = 0u; i <= left.argument_count; i++)
    {
        uint left_root = left.subject_root; uint right_root = right.subject_root;
        if (i != 0u)
        {
            left_root = left.first_argument + (i - 1u);
            right_root = right.first_argument + (i - 1u);
        }
        if (!ts_equal_admitted_goal_roots(left_root, left.environment,
            right_root, right.environment)) return false;
    }
    return true;
}

public EvidenceStatus ts_environment_is_closed(uint environment, uint visible_owner, out bool closed)
{
    closed = true; uint4 env;
    if (!ts_environment_header(environment, env)) return ts_invalid(1u, environment, TS_INVALID);
    // Admission already proved full structural validity. The second pass only
    // classifies remaining exact caller parameters, including unused bindings.
    for (uint i = 0u; i < env.z; i++)
    {
        uint root; uint visits;
        if (!ts_word(12u, env.y + i, 2u, root)) return ts_invalid(1u, environment, env.y + i);
        EvidenceStatus status = ts_admit_root(root, TS_INVALID, visible_owner, true, visits);
        if (status.state == TS_INVALID_INPUT && status.detail == 10u) { closed = false; continue; }
        if (status.state != TS_VALID) return status;
    }
    return ts_ok();
}
