import primitive_types;
import constant_value;
import type_checker.concrete_type_equality;
// One structural constraint engine for one-way matching and two-sided head
// overlap. Both use admitted immutable graphs and exact selected-owner atoms.
// No source environments, prerequisite solving, or proof publication occurs
// here. The caller retains one state across subject and all ordered operands.
import type_checker.owned_type_constraint_contract;
import type_checker.type_constraint_structure;

public OwnedConstraintStatus owned_constraint_initialize<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    uint2 owners, uint2 node_capacities, uint identity_capacity,
    bool overlap, OwnedConstraintLimits limits, out OwnedConstraintState state)
{
    state = (OwnedConstraintState)0;
    state.status = owned_constraint_ok();
    state.owners = owners;
    state.node_capacities = node_capacities;
    state.identity_capacity = identity_capacity;
    state.overlap = overlap ? 1u : 0u;
    state.limits = limits;
    for (uint i = 0u; i < OWNED_CONSTRAINT_BINDINGS; i++)
        state.bindings[i] = uint4(OWNED_CONSTRAINT_INVALID, 0u, OWNED_CONSTRAINT_INVALID, 0u);
    if (limits.depth == 0u)
        state.status = owned_constraint_result(OWNED_CONSTRAINT_RESOURCE_LIMIT, 5u, 1u, 0u);
    else if (limits.depth > OWNED_CONSTRAINT_STACK)
        state.status = owned_constraint_result(OWNED_CONSTRAINT_RESOURCE_LIMIT,
            5u, limits.depth, OWNED_CONSTRAINT_STACK);
    else if (identity_capacity == OWNED_CONSTRAINT_INVALID ||
        any(node_capacities == uint2(OWNED_CONSTRAINT_INVALID, OWNED_CONSTRAINT_INVALID)) ||
        owners.x == OWNED_CONSTRAINT_INVALID ||
        (overlap && owners.y == OWNED_CONSTRAINT_INVALID))
        state.status = owned_constraint_invalid(1u);
    else if (!LeftGraph.owner_parameter_count(owners.x, false, state.counts.x) ||
        !LeftGraph.owner_parameter_count(owners.x, true, state.counts.y) ||
        !RightGraph.owner_parameter_count(owners.y, false, state.counts.z) ||
        !RightGraph.owner_parameter_count(owners.y, true, state.counts.w))
        state.status = owned_constraint_invalid(3u);
    else
    {
        for (uint domain = 0u; domain < 4u; domain++)
        {
            if (state.counts[domain] > 32u)
            {
                state.status = owned_constraint_result(OWNED_CONSTRAINT_RESOURCE_LIMIT,
                    3u, state.counts[domain], 32u);
                break;
            }
        }
    }
    return state.status;
}

bool owned_constraint_constant(uint tag)
{ return tag == 0x80000001u || tag == 0x80000002u || tag == 0x80000003u; }

#include "owned_constant_constraints.slang"

OwnedConstraintStatus owned_constraint_term_shape<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    uint3 term, uint2 node_capacities)
{
    if (term.x > 1u || term.z == OWNED_CONSTRAINT_INVALID)
        return owned_constraint_invalid(1u);
    if (term.y == 1u)
        return term.z > 0u && term.z < 128u ? owned_constraint_ok() : owned_constraint_invalid(1u);
    if (term.y == 3u)
        return term.z < node_capacities[term.x]
            ? owned_constraint_ok() : owned_constraint_invalid(1u);
    if (term.y == 0x80000001u || term.y == 0x80000003u) return owned_constraint_ok();
    if (term.y != 2u && term.y != 0x80000002u) return owned_constraint_invalid(2u);
    bool constant = term.y == 0x80000002u;
    bool valid = term.x == 0u ? LeftGraph.parameter_is_valid(term.z, constant)
                             : RightGraph.parameter_is_valid(term.z, constant);
    return valid ? owned_constraint_ok() : owned_constraint_invalid(3u);
}

// Type operands reach this helper only after constant roots have been handled.
// Keeping that established domain here avoids embedding an unreachable full
// constant traversal at both type-operand call sites. Binding traversal and its
// validation/budget order remain identical to the shared resolver below.
// A goal-side atom is rigid even when its numeric atom equals the pattern.
OwnedConstraintStatus owned_constraint_resolve_type<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    inout uint3 term, inout OwnedConstraintState state, out uint variable)
{
    variable = OWNED_CONSTRAINT_INVALID;
    uint4 visited = uint4(0u, 0u, 0u, 0u);
    for (;;)
    {
        OwnedConstraintStatus status = owned_constraint_term_shape<LeftGraph, RightGraph>(term, state.node_capacities);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        if (term.y != 2u && term.y != 0x80000002u) return owned_constraint_ok();
        bool constant = term.y == 0x80000002u;
        uint index;
        uint classification = term.x == 0u
            ? LeftGraph.owned_parameter(state.owners.x, term.z, constant, index)
            : RightGraph.owned_parameter(state.owners.y, term.z, constant, index);
        if (classification == OWNED_PARAMETER_RIGID) return owned_constraint_ok();
        if (classification != OWNED_PARAMETER_BINDABLE) return owned_constraint_invalid(3u);
        uint domain = term.x * 2u + (constant ? 1u : 0u);
        if (index >= state.counts[domain] || index >= 32u)
            return owned_constraint_invalid(3u);
        uint bit = 1u << index;
        state.seen[domain] |= bit;
        variable = domain * 32u + index;
        if ((state.bound[domain] & bit) == 0u) return owned_constraint_ok();
        if ((visited[domain] & bit) != 0u) return owned_constraint_invalid(9u);
        visited[domain] |= bit;
        if (state.work.substitution_steps >= state.limits.substitution_steps)
            return owned_constraint_limit(8u, state.work.substitution_steps, state.limits.substitution_steps);
        state.work.substitution_steps++;
        term = state.bindings[variable].xyz;
        variable = OWNED_CONSTRAINT_INVALID;
    }
}

// Variable equivalence follows exact side/owner/domain/index keys. This entry
// retains both domains for callers such as the occurs traversal.
OwnedConstraintStatus owned_constraint_resolve<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    inout uint3 term, inout OwnedConstraintState state, out uint variable)
{
    variable = OWNED_CONSTRAINT_INVALID;
    if (owned_constraint_constant(term.y))
    {
        OwnedConstantResolution value;
        OwnedConstraintStatus status = owned_constant_resolve<LeftGraph, RightGraph>(term, state, value);
        if (status.state == OWNED_CONSTRAINT_MATCHED)
        { term = value.terminal; variable = value.variable; }
        return status;
    }
    return owned_constraint_resolve_type<LeftGraph, RightGraph>(term, state, variable);
}

OwnedConstraintStatus owned_constraint_header<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    uint3 term, uint2 node_capacities, uint identity_capacity, out ConstraintNodeHeader header)
{
    header = (ConstraintNodeHeader)0;
    if (term.x > 1u || term.y != 3u) return owned_constraint_invalid(1u);
    bool valid = term.x == 0u
        ? constraint_node_header<LeftGraph>(term.z, node_capacities.x, identity_capacity, header)
        : constraint_node_header<RightGraph>(term.z, node_capacities.y, identity_capacity, header);
    return valid ? owned_constraint_ok() : owned_constraint_invalid(1u);
}

uint owned_constraint_child_count(ConstraintNodeHeader header)
{ return header.kind == 2u ? 2u : header.arity; }

OwnedConstraintStatus owned_constraint_child<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    uint3 term, uint slot, uint2 node_capacities, uint identity_capacity, out uint3 child)
{
    child = uint3(term.x, 0u, OWNED_CONSTRAINT_INVALID);
    ConstraintNodeHeader header;
    OwnedConstraintStatus status = owned_constraint_header<LeftGraph, RightGraph>(term, node_capacities, identity_capacity, header);
    if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
    if (slot >= owned_constraint_child_count(header)) return owned_constraint_invalid(1u);
    uint2 value;
    if (header.kind == 2u && slot == 1u)
    {
        value = term.x == 0u ? constraint_array_length<LeftGraph>(term.z)
                            : constraint_array_length<RightGraph>(term.z);
        if (value.x < 1u || value.x > 3u) return owned_constraint_invalid(2u);
        value.x |= OWNED_CONSTRAINT_CONSTANT;
    }
    else
    {
        bool valid = term.x == 0u
            ? constraint_node_child<LeftGraph>(term.z, header.kind, slot, value)
            : constraint_node_child<RightGraph>(term.z, header.kind, slot, value);
        if (!valid) return owned_constraint_invalid(1u);
        if (header.kind != 1u && owned_constraint_constant(value.x))
            return owned_constraint_invalid(2u);
    }
    child = uint3(term.x, value.x, value.y);
    return owned_constraint_term_shape<LeftGraph, RightGraph>(child, node_capacities);
}

// Full occurs check follows prior bindings. It charges a separate traversal
// budget, including repeated DAG edges. A target occurrence means NoMatch
// (there is no finite unifier); malformed graph/substitution cycles are Invalid.
OwnedConstraintStatus owned_constraint_occurs<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    uint variable, uint3 term, inout OwnedConstraintState state)
{
    uint3 terms[64]; uint next[64]; uint counts[64];
    uint depth = 0u;
    terms[0u] = term; next[0u] = OWNED_CONSTRAINT_INVALID;
    for (;;)
    {
        term = terms[depth];
        if (next[depth] == OWNED_CONSTRAINT_INVALID)
        {
            if (state.work.occurs_visits >= state.limits.occurs_visits)
                return owned_constraint_limit(7u, state.work.occurs_visits, state.limits.occurs_visits);
            state.work.occurs_visits++;
            uint found;
            OwnedConstraintStatus status = owned_constraint_resolve<LeftGraph, RightGraph>(term, state, found);
            if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
            if (variable != OWNED_CONSTRAINT_INVALID && found == variable)
                return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
            terms[depth] = term; next[depth] = 0u; counts[depth] = 0u;
            if (term.y == 3u)
            {
                for (uint ancestor = 0u; ancestor < depth; ancestor++)
                    if (all(terms[ancestor] == term)) return owned_constraint_invalid(9u);
                ConstraintNodeHeader header;
                status = owned_constraint_header<LeftGraph, RightGraph>(term, state.node_capacities, state.identity_capacity, header);
                if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
                counts[depth] = owned_constraint_child_count(header);
            }
        }
        if (next[depth] == counts[depth])
        {
            if (depth == 0u) return owned_constraint_ok();
            depth--; continue;
        }
        uint3 child;
        OwnedConstraintStatus status = owned_constraint_child<LeftGraph, RightGraph>(
            term, next[depth]++, state.node_capacities, state.identity_capacity, child);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        if (depth + 1u >= state.limits.depth)
            return owned_constraint_limit(5u, depth + 1u, state.limits.depth);
        depth++; terms[depth] = child; next[depth] = OWNED_CONSTRAINT_INVALID;
    }
}

// Select the binding operation itself at specialization time. A mode value
// used only as a runtime branch can retain an unreachable occurs traversal at
// O0; the one-way operation below has no reference to that traversal at all.
interface IOwnedConstraintBindingOperation
{
    static uint mode();
    static OwnedConstraintStatus validate(uint variable, uint3 term,
        inout OwnedConstraintState state);
}
struct OwnedOneWayBindingOperation : IOwnedConstraintBindingOperation
{
    static uint mode() { return 0u; }
    static OwnedConstraintStatus validate(uint variable, uint3 term,
        inout OwnedConstraintState state)
    {
        // Only the rigid, pre-admitted normalized goal can be captured. It
        // cannot contain a bindable pattern role, so no occurs scan is needed.
        return term.x == 1u ? owned_constraint_ok() : owned_constraint_invalid(3u);
    }
}
struct OwnedOverlapBindingOperation<
    LeftGraph : IOwnedConstraintPatternGraph,
    RightGraph : IOwnedConstraintPatternGraph> : IOwnedConstraintBindingOperation
{
    static uint mode() { return 1u; }
    static OwnedConstraintStatus validate(uint variable, uint3 term,
        inout OwnedConstraintState state)
    {
        return owned_constraint_occurs<LeftGraph, RightGraph>(variable, term, state);
    }
}

OwnedConstraintStatus owned_constraint_bind<Operation : IOwnedConstraintBindingOperation>(
    uint variable, uint3 term, inout OwnedConstraintState state)
{
    if (variable >= OWNED_CONSTRAINT_BINDINGS) return owned_constraint_invalid(3u);
    uint domain = variable / 32u; uint index = variable % 32u;
    if (index >= state.counts[domain] ||
        ((domain & 1u) != 0u) != owned_constraint_constant(term.y))
        return owned_constraint_invalid(2u);
    // No binding is installed until the selected operation succeeds. Overlap
    // retains the complete occurs check; one-way retains its rigid-side check.
    OwnedConstraintStatus status = Operation.validate(variable, term, state);
    if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
    state.bindings[variable] = uint4(term, 0u);
    state.bound[domain] |= 1u << index;
    return owned_constraint_ok();
}

#include "owned_constant_unification.slang"

OwnedConstraintStatus owned_constraint_unify_root<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph,
    Operation : IOwnedConstraintBindingOperation>(
    uint2 left, uint2 right, bool allow_inference, inout OwnedConstraintState state)
{
    // Public wrappers retain their original checks. Mode stays immutable
    // throughout this shared traversal and agrees with its static operation.
    if (Operation.mode() > 1u || state.overlap != Operation.mode())
        return owned_constraint_invalid(3u);
    uint3 left_terms[64]; uint3 right_terms[64];
    uint next[64]; uint counts[64]; bool count_domain[64]; uint depth = 0u;
    left_terms[0u] = uint3(0u, left.x, left.y);
    right_terms[0u] = uint3(1u, right.x, right.y);
    next[0u] = OWNED_CONSTRAINT_INVALID; count_domain[0u] = false;
    for (;;)
    {
        uint3 a = left_terms[depth]; uint3 b = right_terms[depth];
        if (next[depth] == OWNED_CONSTRAINT_INVALID)
        {
            if (state.work.pair_visits >= state.limits.pair_visits)
                return owned_constraint_limit(6u, state.work.pair_visits, state.limits.pair_visits);
            state.work.pair_visits++;
            bool a_constant = owned_constraint_constant(a.y);
            bool b_constant = owned_constraint_constant(b.y);
            if (a_constant || b_constant)
            {
                if (!a_constant || !b_constant)
                    return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
                OwnedConstraintStatus constant_status = owned_constant_unify<LeftGraph, RightGraph, Operation>(
                    a, b, count_domain[depth], allow_inference, state);
                if (constant_status.state != OWNED_CONSTRAINT_MATCHED) return constant_status;
                next[depth] = 0u; counts[depth] = 0u;
                if (depth == 0u) return owned_constraint_ok();
                depth--; continue;
            }
            uint a_variable; uint b_variable;
            // The constant branch above returned or continued, so neither
            // root can require the constant resolver at this point.
            OwnedConstraintStatus status = owned_constraint_resolve_type<LeftGraph, RightGraph>(a, state, a_variable);
            if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
            status = owned_constraint_resolve_type<LeftGraph, RightGraph>(b, state, b_variable);
            if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
            left_terms[depth] = a; right_terms[depth] = b;
            next[depth] = 0u; counts[depth] = 0u;
            if (owned_constraint_constant(a.y) != owned_constraint_constant(b.y))
                return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
            if (a_variable != OWNED_CONSTRAINT_INVALID || b_variable != OWNED_CONSTRAINT_INVALID)
            {
                if (!allow_inference) return owned_constraint_invalid(4u);
                if (a_variable != b_variable)
                {
                    // Select operands before the call: two conditional call
                    // sites inline two complete occurs traversals and stacks.
                    bool bind_left = a_variable != OWNED_CONSTRAINT_INVALID;
                    uint variable = bind_left ? a_variable : b_variable;
                    uint3 value = bind_left ? b : a;
                    status = owned_constraint_bind<Operation>(variable, value, state);
                    if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
                }
            }
            else if (a.y != b.y)
                return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
            else if (a.y != 3u)
            {
                // Atomic identity is shared across adapters; graph side is
                // relevant only for bindable roles and compound row addresses.
                if (a.z != b.z) return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
            }
            else
            {
                for (uint ancestor = 0u; ancestor < depth; ancestor++)
                    if (all(left_terms[ancestor] == a) && all(right_terms[ancestor] == b))
                        return owned_constraint_invalid(9u);
                ConstraintNodeHeader a_header; ConstraintNodeHeader b_header;
                status = owned_constraint_header<LeftGraph, RightGraph>(a, state.node_capacities, state.identity_capacity, a_header);
                if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
                status = owned_constraint_header<LeftGraph, RightGraph>(b, state.node_capacities, state.identity_capacity, b_header);
                if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
                if (a_header.kind != b_header.kind ||
                    (a_header.kind == 1u && !constraint_nominal_headers_equal(a_header, b_header)))
                    return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
                counts[depth] = owned_constraint_child_count(a_header);
            }
        }
        if (next[depth] == counts[depth])
        {
            if (depth == 0u) return owned_constraint_ok();
            depth--; continue;
        }
        uint slot = next[depth]++;
        uint3 a_child; uint3 b_child;
        OwnedConstraintStatus status = owned_constraint_child<LeftGraph, RightGraph>(a, slot, state.node_capacities, state.identity_capacity, a_child);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        status = owned_constraint_child<LeftGraph, RightGraph>(b, slot, state.node_capacities, state.identity_capacity, b_child);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        if (depth + 1u >= state.limits.depth)
            return owned_constraint_limit(5u, depth + 1u, state.limits.depth);
        ConstraintNodeHeader parent_header;
        status = owned_constraint_header<LeftGraph, RightGraph>(a, state.node_capacities,
            state.identity_capacity, parent_header);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        bool child_count_domain = parent_header.kind == 2u && slot == 1u;
        depth++; left_terms[depth] = a_child; right_terms[depth] = b_child;
        count_domain[depth] = child_count_domain;
        next[depth] = OWNED_CONSTRAINT_INVALID;
    }
}

public OwnedConstraintStatus owned_constraints_begin<PatternGraph : IOwnedConstraintPatternGraph>(
    uint owner, uint pattern_node_capacity, uint goal_node_capacity, uint identity_capacity,
    OwnedConstraintLimits limits, out OwnedConstraintState state)
{
    // GoalGraph does not participate in initialization: use a zero-inventory
    // pattern wrapper solely for its owner-count implementation.
    return owned_constraint_initialize<PatternGraph, RigidConstraintGoalGraph<PatternGraph>>(
        uint2(owner, OWNED_CONSTRAINT_INVALID), uint2(pattern_node_capacity, goal_node_capacity),
        identity_capacity, false, limits, state);
}

public OwnedConstraintStatus owned_constraints_match<
    PatternGraph : IOwnedConstraintPatternGraph, GoalGraph : IConstraintMatchGraph>(
    uint2 pattern, uint2 goal, inout OwnedConstraintState state)
{
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return state.status;
    if (state.finished != 0u || state.overlap != 0u || state.owners.y != OWNED_CONSTRAINT_INVALID || any(state.counts.zw != uint2(0u, 0u)))
        state.status = owned_constraint_invalid(3u);
    else state.status = owned_constraint_unify_root<PatternGraph,
        RigidConstraintGoalGraph<GoalGraph>, OwnedOneWayBindingOperation>(
        pattern, goal, true, state);
    return state.status;
}

public OwnedConstraintStatus owned_constraints_finish<
    PatternGraph : IOwnedConstraintPatternGraph, GoalGraph : IConstraintMatchGraph>(
    inout OwnedConstraintState state)
{
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return state.status;
    if (state.overlap != 0u) state.status = owned_constraint_invalid(3u);
    else for (uint domain = 0u; domain < 2u; domain++)
    {
        uint expected = owned_constraint_mask(state.counts[domain]);
        if (state.seen[domain] != expected || state.bound[domain] != expected)
        { state.status = owned_constraint_invalid(4u); break; }
    }
    if (state.status.state == OWNED_CONSTRAINT_MATCHED)
        state.status = owned_constant_recheck_fits<PatternGraph, RigidConstraintGoalGraph<GoalGraph>>(state);
    if (state.status.state == OWNED_CONSTRAINT_MATCHED) state.finished = 1u;
    return state.status;
}

// Recheck an instantiated prerequisite against its normalized conclusion.
// A successful complete head match freezes every owned parameter. This call
// retains budgets and bindings, forbids inference, and never substitutes a
// goal-side term again. PatternGraph/GoalGraph and their admitted storage must
// be the same immutable graph capabilities used for the completed head match.
public OwnedConstraintStatus owned_constraints_match_fixed<
    PatternGraph : IOwnedConstraintPatternGraph, GoalGraph : IConstraintMatchGraph>(
    uint2 pattern, uint2 goal, inout OwnedConstraintState state)
{
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return state.status;
    if (state.finished == 0u || state.overlap != 0u ||
        state.owners.y != OWNED_CONSTRAINT_INVALID || any(state.counts.zw != uint2(0u, 0u)))
        state.status = owned_constraint_invalid(3u);
    else
    {
        for (uint domain = 0u; domain < 2u; domain++)
        {
            uint expected = owned_constraint_mask(state.counts[domain]);
            if (state.seen[domain] != expected || state.bound[domain] != expected)
            { state.status = owned_constraint_invalid(4u); break; }
        }
        if (state.status.state == OWNED_CONSTRAINT_MATCHED)
            state.status = owned_constraint_unify_root<PatternGraph,
                RigidConstraintGoalGraph<GoalGraph>, OwnedOneWayBindingOperation>(
                pattern, goal, false, state);
    }
    return state.status;
}

public bool owned_constraint_binding<
    PatternGraph : IOwnedConstraintPatternGraph, GoalGraph : IConstraintMatchGraph>(
    inout OwnedConstraintState state, bool constant, uint index,
    out OwnedConstraintBindingRequest request)
{
    request = (OwnedConstraintBindingRequest)0;
    request.reference = uint3(0u, 0u, OWNED_CONSTRAINT_INVALID);
    uint domain = constant ? 1u : 0u;
    if (state.status.state != OWNED_CONSTRAINT_MATCHED || state.finished == 0u || state.overlap != 0u ||
        index >= state.counts[domain] || index >= 32u ||
        (state.bound[domain] & (1u << index)) == 0u) return false;
    if (constant)
    {
        OwnedConstantResolution value;
        state.status = owned_constant_resolve<PatternGraph, RigidConstraintGoalGraph<GoalGraph>>(
            state.constant_parameters[index], state, value);
        if (state.status.state != OWNED_CONSTRAINT_MATCHED) return false;
        if (value.terminal.x != 1u || value.variable != OWNED_CONSTRAINT_INVALID)
        { state.status = owned_constraint_invalid(3u); return false; }
        request.reference = value.terminal; request.target_count = value.target_count;
        for (uint target = 0u; target < value.target_count; target++)
            request.target_scalars[target] = value.target_scalars[target];
    }
    else
    {
        uint4 binding = state.bindings[index];
        if (binding.x != 1u || owned_constraint_constant(binding.y) || binding.w != 0u)
        { state.status = owned_constraint_invalid(2u); return false; }
        request.reference = binding.xyz;
    }
    return true;
}

public OwnedConstraintStatus owned_overlap_begin<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    uint left_owner, uint right_owner, uint left_node_capacity, uint right_node_capacity,
    uint identity_capacity, OwnedConstraintLimits limits, out OwnedConstraintState state)
{
    return owned_constraint_initialize<LeftGraph, RightGraph>(uint2(left_owner, right_owner),
        uint2(left_node_capacity, right_node_capacity), identity_capacity, true, limits, state);
}

public OwnedConstraintStatus owned_overlap_match<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    uint2 left, uint2 right, inout OwnedConstraintState state)
{
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return state.status;
    if (state.finished != 0u || state.overlap != 1u) state.status = owned_constraint_invalid(3u);
    else state.status = owned_constraint_unify_root<LeftGraph, RightGraph,
        OwnedOverlapBindingOperation<LeftGraph, RightGraph>>(left, right, true, state);
    return state.status;
}

public OwnedConstraintStatus owned_overlap_finish<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    inout OwnedConstraintState state)
{
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return state.status;
    if (state.overlap != 1u) state.status = owned_constraint_invalid(3u);
    else for (uint domain = 0u; domain < 4u; domain++)
    {
        // A free representative is an existential solution, not a missing
        // inferred argument: T and U overlap. Every declared parameter still
        // must occur somewhere in its complete implementation head.
        if (state.seen[domain] != owned_constraint_mask(state.counts[domain]))
        { state.status = owned_constraint_invalid(4u); break; }
    }
    if (state.status.state == OWNED_CONSTRAINT_MATCHED)
        state.status = owned_constant_recheck_fits<LeftGraph, RightGraph>(state);
    if (state.status.state == OWNED_CONSTRAINT_MATCHED) state.finished = 1u;
    return state.status;
}

// Definition admission visits EVERY head root independently of candidate
// comparisons. In particular, NoMatch must never hide an unconstrained header
// parameter or a malformed unused branch. Caller supplies subject followed by
// all ordered trait operands and admits their type/constant root roles.
public OwnedConstraintStatus owned_pattern_begin<PatternGraph : IOwnedConstraintPatternGraph>(
    uint owner, uint node_capacity, uint identity_capacity,
    OwnedConstraintLimits limits, out OwnedConstraintState state)
{
    OwnedConstraintStatus status = owned_constraints_begin<PatternGraph>(
        owner, node_capacity, 0u, identity_capacity, limits, state);
    state.overlap = 2u;
    return status;
}

public OwnedConstraintStatus owned_pattern_visit<PatternGraph : IOwnedConstraintPatternGraph>(
    uint2 root, inout OwnedConstraintState state)
{
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return state.status;
    if (state.overlap != 2u || state.finished != 0u)
        state.status = owned_constraint_invalid(3u);
    else state.status = owned_constraint_occurs<PatternGraph, RigidConstraintGoalGraph<PatternGraph>>(
        OWNED_CONSTRAINT_INVALID, uint3(0u, root.x, root.y), state);
    return state.status;
}

public OwnedConstraintStatus owned_pattern_finish<PatternGraph : IOwnedConstraintPatternGraph>(
    inout OwnedConstraintState state)
{
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return state.status;
    if (state.overlap != 2u) state.status = owned_constraint_invalid(3u);
    else for (uint domain = 0u; domain < 2u; domain++)
    {
        if (state.seen[domain] != owned_constraint_mask(state.counts[domain]) ||
            state.bound[domain] != 0u)
        { state.status = owned_constraint_invalid(4u); break; }
    }
    if (state.status.state == OWNED_CONSTRAINT_MATCHED)
        state.status = owned_constant_recheck_fits<PatternGraph, RigidConstraintGoalGraph<PatternGraph>>(state);
    if (state.status.state == OWNED_CONSTRAINT_MATCHED) state.finished = 1u;
    return state.status;
}
