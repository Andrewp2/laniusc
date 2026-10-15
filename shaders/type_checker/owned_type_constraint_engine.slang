import primitive_types;
import constant_value;
import type_checker.concrete_type_equality;
// One structural constraint engine for one-way matching and two-sided head
// overlap. Both use admitted immutable graphs and exact selected-owner atoms.
// No source environments, prerequisite solving, or proof publication occurs
// here. The caller retains one state across subject and all ordered operands.
import type_checker.owned_type_constraint_contract;
import type_checker.type_constraint_structure;
import thread_scratch;

// Side-indexed graph capabilities. The engine calls each capability from one
// site with the term's graph side (0 = left/pattern, otherwise right/goal);
// a pair dispatches to its two graphs. A pair over one graph shares that
// graph's code for both sides, so drivers inline it once per site.
interface IOwnedConstraintPair
{
    static bool parameter_is_valid(uint side, uint reference, bool constant);
    static bool owner_parameter_count(uint side, uint owner, bool constant, out uint count);
    static uint owned_parameter(uint side, uint owner, uint reference, bool constant, out uint index);
    static bool node_header(uint side, uint node, uint node_capacity, uint identity_capacity,
        out ConstraintNodeHeader header);
    static bool node_child(uint side, uint node, uint kind, uint slot, out uint2 child);
    static uint2 array_length(uint side, uint node);
    static uint constant_scalar(uint side, uint2 reference);
    static uint parameter_scalar(uint side, uint parameter);
    static bool constant_value(uint side, uint row, out uint3 value);
    static bool constant_projection(uint side, uint row, out uint scalar, out uint2 child);
}

struct OwnedConstraintGraphPair<LeftGraph : IOwnedConstraintPatternGraph,
    RightGraph : IOwnedConstraintPatternGraph> : IOwnedConstraintPair
{
    static bool parameter_is_valid(uint side, uint reference, bool constant)
    {
        if (side == 0u) return LeftGraph.parameter_is_valid(reference, constant);
        return RightGraph.parameter_is_valid(reference, constant);
    }
    static bool owner_parameter_count(uint side, uint owner, bool constant, out uint count)
    {
        if (side == 0u) return LeftGraph.owner_parameter_count(owner, constant, count);
        return RightGraph.owner_parameter_count(owner, constant, count);
    }
    static uint owned_parameter(uint side, uint owner, uint reference, bool constant, out uint index)
    {
        if (side == 0u) return LeftGraph.owned_parameter(owner, reference, constant, index);
        return RightGraph.owned_parameter(owner, reference, constant, index);
    }
    static bool node_header(uint side, uint node, uint node_capacity, uint identity_capacity,
        out ConstraintNodeHeader header)
    {
        if (side == 0u) return constraint_node_header<LeftGraph>(node, node_capacity, identity_capacity, header);
        return constraint_node_header<RightGraph>(node, node_capacity, identity_capacity, header);
    }
    static bool node_child(uint side, uint node, uint kind, uint slot, out uint2 child)
    {
        if (side == 0u) return constraint_node_child<LeftGraph>(node, kind, slot, child);
        return constraint_node_child<RightGraph>(node, kind, slot, child);
    }
    static uint2 array_length(uint side, uint node)
    {
        if (side == 0u) return constraint_array_length<LeftGraph>(node);
        return constraint_array_length<RightGraph>(node);
    }
    static uint constant_scalar(uint side, uint2 reference)
    {
        if (side == 0u) return constant_reference_scalar<LeftGraph>(reference);
        return constant_reference_scalar<RightGraph>(reference);
    }
    static uint parameter_scalar(uint side, uint parameter)
    {
        if (side == 0u) return LeftGraph.constant_parameter_scalar(parameter);
        return RightGraph.constant_parameter_scalar(parameter);
    }
    static bool constant_value(uint side, uint row, out uint3 value)
    {
        if (side == 0u) return LeftGraph.constant_value(row, value);
        return RightGraph.constant_value(row, value);
    }
    static bool constant_projection(uint side, uint row, out uint scalar, out uint2 child)
    {
        if (side == 0u) return LeftGraph.constant_projection(row, scalar, child);
        return RightGraph.constant_projection(row, scalar, child);
    }
}

// Both sides are the same graph capability (two-sided head overlap).
public struct OwnedConstraintSameGraphPair<Graph : IOwnedConstraintPatternGraph> : IOwnedConstraintPair
{
    static bool parameter_is_valid(uint side, uint reference, bool constant)
    { return Graph.parameter_is_valid(reference, constant); }
    static bool owner_parameter_count(uint side, uint owner, bool constant, out uint count)
    { return Graph.owner_parameter_count(owner, constant, count); }
    static uint owned_parameter(uint side, uint owner, uint reference, bool constant, out uint index)
    { return Graph.owned_parameter(owner, reference, constant, index); }
    static bool node_header(uint side, uint node, uint node_capacity, uint identity_capacity,
        out ConstraintNodeHeader header)
    { return constraint_node_header<Graph>(node, node_capacity, identity_capacity, header); }
    static bool node_child(uint side, uint node, uint kind, uint slot, out uint2 child)
    { return constraint_node_child<Graph>(node, kind, slot, child); }
    static uint2 array_length(uint side, uint node)
    { return constraint_array_length<Graph>(node); }
    static uint constant_scalar(uint side, uint2 reference)
    { return constant_reference_scalar<Graph>(reference); }
    static uint parameter_scalar(uint side, uint parameter)
    { return Graph.constant_parameter_scalar(parameter); }
    static bool constant_value(uint side, uint row, out uint3 value)
    { return Graph.constant_value(row, value); }
    static bool constant_projection(uint side, uint row, out uint scalar, out uint2 child)
    { return Graph.constant_projection(row, scalar, child); }
}

// Pattern graph against RigidConstraintGoalGraph<Pattern>: the rigid side
// exposes the pattern's own graph capabilities, and only parameter ownership
// differs by side (exactly RigidConstraintGoalGraph's owner/slot methods).
struct OwnedConstraintSelfRigidPair<Pattern : IOwnedConstraintPatternGraph> : IOwnedConstraintPair
{
    static bool parameter_is_valid(uint side, uint reference, bool constant)
    { return Pattern.parameter_is_valid(reference, constant); }
    static bool owner_parameter_count(uint side, uint owner, bool constant, out uint count)
    {
        if (side == 0u) return Pattern.owner_parameter_count(owner, constant, count);
        count = 0u; return owner == OWNED_CONSTRAINT_INVALID;
    }
    static uint owned_parameter(uint side, uint owner, uint reference, bool constant, out uint index)
    {
        if (side == 0u) return Pattern.owned_parameter(owner, reference, constant, index);
        index = OWNED_CONSTRAINT_INVALID;
        return owner == OWNED_CONSTRAINT_INVALID && Pattern.parameter_is_valid(reference, constant)
            ? OWNED_PARAMETER_RIGID : OWNED_PARAMETER_INVALID;
    }
    static bool node_header(uint side, uint node, uint node_capacity, uint identity_capacity,
        out ConstraintNodeHeader header)
    { return constraint_node_header<Pattern>(node, node_capacity, identity_capacity, header); }
    static bool node_child(uint side, uint node, uint kind, uint slot, out uint2 child)
    { return constraint_node_child<Pattern>(node, kind, slot, child); }
    static uint2 array_length(uint side, uint node)
    { return constraint_array_length<Pattern>(node); }
    static uint constant_scalar(uint side, uint2 reference)
    { return constant_reference_scalar<Pattern>(reference); }
    static uint parameter_scalar(uint side, uint parameter)
    { return Pattern.constant_parameter_scalar(parameter); }
    static bool constant_value(uint side, uint row, out uint3 value)
    { return Pattern.constant_value(row, value); }
    static bool constant_projection(uint side, uint row, out uint scalar, out uint2 child)
    { return Pattern.constant_projection(row, scalar, child); }
}

// The frame is never cleared: a binding cell is read only for a bound
// variable and a constant cell only for a seen one, after this state wrote it.
OwnedConstraintStatus owned_constraint_initialize<Pair : IOwnedConstraintPair>(
    uint2 owners, uint2 node_capacities, uint identity_capacity,
    bool overlap, OwnedConstraintLimits limits, uint frame, out OwnedConstraintState state)
{
    state = (OwnedConstraintState)0;
    state.status = owned_constraint_ok();
    state.owners = owners;
    state.node_capacities = node_capacities;
    state.identity_capacity = identity_capacity;
    state.overlap = overlap ? 1u : 0u;
    state.limits = limits;
    state.frame = frame;
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
    else
    {
        // Inventory left type, left constant, right type, right constant;
        // the first unknown owner stops the sequence.
        [loop]
        for (uint domain = 0u; domain < 4u; domain++)
        {
            uint side = domain >> 1u; uint count;
            bool known = Pair.owner_parameter_count(side, select(side == 0u, owners.x, owners.y),
                (domain & 1u) != 0u, count);
            state.counts[domain] = count;
            if (!known) { state.status = owned_constraint_invalid(3u); break; }
        }
        if (state.status.state == OWNED_CONSTRAINT_MATCHED)
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
    }
    return state.status;
}

bool owned_constraint_constant(uint tag)
{ return tag == 0x80000001u || tag == 0x80000002u || tag == 0x80000003u; }

#include "owned_constant_constraints.slang"

OwnedConstraintStatus owned_constraint_term_shape<Pair : IOwnedConstraintPair>(
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
    return Pair.parameter_is_valid(term.x, term.z, constant)
        ? owned_constraint_ok() : owned_constraint_invalid(3u);
}

// Type operands reach this helper only after constant roots have been handled.
// Keeping that established domain here avoids embedding an unreachable full
// constant traversal at both type-operand call sites. Binding traversal and its
// validation/budget order remain identical to the shared resolver below.
// A goal-side atom is rigid even when its numeric atom equals the pattern.
OwnedConstraintStatus owned_constraint_resolve_type<Pair : IOwnedConstraintPair>(
    inout uint3 term, inout OwnedConstraintState state, out uint variable)
{
    variable = OWNED_CONSTRAINT_INVALID;
    uint4 visited = uint4(0u, 0u, 0u, 0u);
    for (;;)
    {
        OwnedConstraintStatus status = owned_constraint_term_shape<Pair>(term, state.node_capacities);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        if (term.y != 2u && term.y != 0x80000002u) return owned_constraint_ok();
        bool constant = term.y == 0x80000002u;
        uint index;
        uint classification = Pair.owned_parameter(term.x,
            select(term.x == 0u, state.owners.x, state.owners.y), term.z, constant, index);
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
        term = owned_constraint_binding_cell(state.frame, variable).xyz;
        variable = OWNED_CONSTRAINT_INVALID;
    }
}

// Variable equivalence follows exact side/owner/domain/index keys. This entry
// retains both domains for callers such as the occurs traversal.
OwnedConstraintStatus owned_constraint_resolve<Pair : IOwnedConstraintPair>(
    inout uint3 term, inout OwnedConstraintState state, out uint variable)
{
    variable = OWNED_CONSTRAINT_INVALID;
    if (owned_constraint_constant(term.y))
    {
        OwnedConstantResolution value;
        OwnedConstraintStatus status = owned_constant_resolve<Pair>(term, OWNED_TARGETS_DISCARD, state, value);
        if (status.state == OWNED_CONSTRAINT_MATCHED)
        { term = value.terminal; variable = value.variable; }
        return status;
    }
    return owned_constraint_resolve_type<Pair>(term, state, variable);
}

OwnedConstraintStatus owned_constraint_header<Pair : IOwnedConstraintPair>(
    uint3 term, uint2 node_capacities, uint identity_capacity, out ConstraintNodeHeader header)
{
    header = (ConstraintNodeHeader)0;
    if (term.x > 1u || term.y != 3u) return owned_constraint_invalid(1u);
    bool valid = Pair.node_header(term.x, term.z,
        select(term.x == 0u, node_capacities.x, node_capacities.y), identity_capacity, header);
    return valid ? owned_constraint_ok() : owned_constraint_invalid(1u);
}

uint owned_constraint_child_count(ConstraintNodeHeader header)
{ return header.kind == 2u ? 2u : header.arity; }

// The caller visited this compound term and retains its admitted header kind
// and child count; reading the immutable header again yields the same values.
OwnedConstraintStatus owned_constraint_child<Pair : IOwnedConstraintPair>(
    uint3 term, uint kind, uint count, uint slot, uint2 node_capacities, out uint3 child)
{
    child = uint3(term.x, 0u, OWNED_CONSTRAINT_INVALID);
    if (slot >= count) return owned_constraint_invalid(1u);
    uint2 value;
    if (kind == 2u && slot == 1u)
    {
        value = Pair.array_length(term.x, term.z);
        if (value.x < 1u || value.x > 3u) return owned_constraint_invalid(2u);
        value.x |= OWNED_CONSTRAINT_CONSTANT;
    }
    else
    {
        if (!Pair.node_child(term.x, term.z, kind, slot, value)) return owned_constraint_invalid(1u);
        if (kind != 1u && owned_constraint_constant(value.x))
            return owned_constraint_invalid(2u);
    }
    child = uint3(term.x, value.x, value.y);
    return owned_constraint_term_shape<Pair>(child, node_capacities);
}

// Full occurs check follows prior bindings. It charges a separate traversal
// budget, including repeated DAG edges. A target occurrence means NoMatch
// (there is no finite unifier); malformed graph/substitution cycles are Invalid.
// The stack lives in thread scratch: per depth, cell0 = (term, next child)
// and cell1 = (child count, kind).
OwnedConstraintStatus owned_constraint_occurs<Pair : IOwnedConstraintPair>(
    uint variable, uint3 term, inout OwnedConstraintState state)
{
    uint depth = 0u;
    scratch_set_cell(SCRATCH_OWNED_OCCURS, uint4(term, OWNED_CONSTRAINT_INVALID));
    for (;;)
    {
        uint frame = SCRATCH_OWNED_OCCURS + depth * 2u;
        uint4 top = scratch_cell(frame);
        term = top.xyz; uint next = top.w;
        if (next == OWNED_CONSTRAINT_INVALID)
        {
            if (state.work.occurs_visits >= state.limits.occurs_visits)
                return owned_constraint_limit(7u, state.work.occurs_visits, state.limits.occurs_visits);
            state.work.occurs_visits++;
            uint found;
            OwnedConstraintStatus status = owned_constraint_resolve<Pair>(term, state, found);
            if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
            if (variable != OWNED_CONSTRAINT_INVALID && found == variable)
                return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
            next = 0u; uint count = 0u; uint kind = 0u;
            if (term.y == 3u)
            {
                for (uint ancestor = 0u; ancestor < depth; ancestor++)
                    if (all(scratch_cell(SCRATCH_OWNED_OCCURS + ancestor * 2u).xyz == term))
                        return owned_constraint_invalid(9u);
                ConstraintNodeHeader header;
                status = owned_constraint_header<Pair>(term, state.node_capacities, state.identity_capacity, header);
                if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
                count = owned_constraint_child_count(header);
                kind = header.kind;
            }
            scratch_set_cell(frame, uint4(term, 0u));
            scratch_set_cell(frame + 1u, uint4(count, kind, 0u, 0u));
        }
        uint2 shape = scratch_cell(frame + 1u).xy;
        if (next == shape.x)
        {
            if (depth == 0u) return owned_constraint_ok();
            depth--; continue;
        }
        scratch_set_word(frame, 3u, next + 1u);
        uint3 child;
        OwnedConstraintStatus status = owned_constraint_child<Pair>(
            term, shape.y, shape.x, next, state.node_capacities, child);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        if (depth + 1u >= state.limits.depth)
            return owned_constraint_limit(5u, depth + 1u, state.limits.depth);
        depth++;
        scratch_set_cell(SCRATCH_OWNED_OCCURS + depth * 2u, uint4(child, OWNED_CONSTRAINT_INVALID));
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
struct OwnedOverlapBindingOperation<Pair : IOwnedConstraintPair> : IOwnedConstraintBindingOperation
{
    static uint mode() { return 1u; }
    static OwnedConstraintStatus validate(uint variable, uint3 term,
        inout OwnedConstraintState state)
    {
        return owned_constraint_occurs<Pair>(variable, term, state);
    }
}

// Type bindings check the variable's slot and domain here. A constant binding
// comes from its own resolver, which already established both (unchecked).
OwnedConstraintStatus owned_constraint_bind<Operation : IOwnedConstraintBindingOperation>(
    uint variable, uint3 term, uint target, bool checked, inout OwnedConstraintState state)
{
    uint domain = variable / 32u; uint index = variable % 32u;
    if (checked)
    {
        if (variable >= OWNED_CONSTRAINT_BINDINGS) return owned_constraint_invalid(3u);
        if (index >= state.counts[domain] ||
            ((domain & 1u) != 0u) != owned_constraint_constant(term.y))
            return owned_constraint_invalid(2u);
    }
    // No binding is installed until the selected operation succeeds. Overlap
    // retains the complete occurs check; one-way retains its rigid-side check.
    OwnedConstraintStatus status = Operation.validate(variable, term, state);
    if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
    owned_constraint_set_binding(state.frame, variable, uint4(term, target));
    state.bound[domain] |= 1u << index;
    return owned_constraint_ok();
}

#include "owned_constant_unification.slang"

OwnedConstraintStatus owned_constraint_unify_root<Pair : IOwnedConstraintPair,
    Operation : IOwnedConstraintBindingOperation>(
    uint2 left, uint2 right, bool allow_inference, inout OwnedConstraintState state)
{
    // Public wrappers retain their original checks. Mode stays immutable
    // throughout this shared traversal and agrees with its static operation.
    if (Operation.mode() > 1u || state.overlap != Operation.mode())
        return owned_constraint_invalid(3u);
    // The stack lives in thread scratch: per depth, cell0 = (left term, next
    // child), cell1 = (right term, child count), cell2 = (kind, count domain).
    uint depth = 0u;
    scratch_set_cell(SCRATCH_OWNED_UNIFY, uint4(0u, left.x, left.y, OWNED_CONSTRAINT_INVALID));
    scratch_set_cell(SCRATCH_OWNED_UNIFY + 1u, uint4(1u, right.x, right.y, 0u));
    scratch_set_cell(SCRATCH_OWNED_UNIFY + 2u, uint4(0u, 0u, 0u, 0u));
    for (;;)
    {
        uint frame = SCRATCH_OWNED_UNIFY + depth * 3u;
        uint4 left_cell = scratch_cell(frame); uint4 right_cell = scratch_cell(frame + 1u);
        uint3 a = left_cell.xyz; uint3 b = right_cell.xyz; uint next = left_cell.w;
        if (next == OWNED_CONSTRAINT_INVALID)
        {
            uint4 shape = scratch_cell(frame + 2u);
            bool count_domain = shape.y != 0u; uint count = 0u; uint kind = shape.x;
            if (state.work.pair_visits >= state.limits.pair_visits)
                return owned_constraint_limit(6u, state.work.pair_visits, state.limits.pair_visits);
            state.work.pair_visits++;
            bool a_constant = owned_constraint_constant(a.y);
            bool b_constant = owned_constraint_constant(b.y);
            // A constant pair, or a type pair that binds one variable, runs the
            // single constant-unification/binding call below, which also holds
            // the one binding (overlap occurs traversal) site.
            OwnedConstantBinding binding = (OwnedConstantBinding)0;
            bool unify = false;
            OwnedConstraintStatus status;
            if (a_constant || b_constant)
            {
                if (!a_constant || !b_constant)
                    return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
                unify = true;
            }
            else
            {
                uint a_variable = OWNED_CONSTRAINT_INVALID; uint b_variable = OWNED_CONSTRAINT_INVALID;
                // Constant pairs took the branch above, so neither
                // root can require the constant resolver at this point. Resolve
                // left then right through one call site.
                [loop]
                for (uint side = 0u; side < 2u; side++)
                {
                    bool first = side == 0u;
                    uint3 term = select(bool3(first, first, first), a, b); uint variable;
                    status = owned_constraint_resolve_type<Pair>(term, state, variable);
                    if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
                    if (first) { a = term; a_variable = variable; }
                    else { b = term; b_variable = variable; }
                }
                kind = 0u;
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
                        binding.bind = 1u;
                        binding.variable = bind_left ? a_variable : b_variable;
                        binding.value = bind_left ? b : a;
                        unify = true;
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
                    {
                        uint ancestor_frame = SCRATCH_OWNED_UNIFY + ancestor * 3u;
                        if (all(scratch_cell(ancestor_frame).xyz == a) &&
                            all(scratch_cell(ancestor_frame + 1u).xyz == b))
                            return owned_constraint_invalid(9u);
                    }
                    ConstraintNodeHeader a_header = (ConstraintNodeHeader)0;
                    ConstraintNodeHeader b_header = (ConstraintNodeHeader)0;
                    [loop]
                    for (uint side = 0u; side < 2u; side++)
                    {
                        bool first = side == 0u; ConstraintNodeHeader header;
                        status = owned_constraint_header<Pair>(select(bool3(first, first, first), a, b),
                            state.node_capacities, state.identity_capacity, header);
                        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
                        if (first) a_header = header; else b_header = header;
                    }
                    if (a_header.kind != b_header.kind ||
                        (a_header.kind == 1u && !constraint_nominal_headers_equal(a_header, b_header)))
                        return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
                    // Equal kinds and (for nominals) equal arities: one count.
                    count = owned_constraint_child_count(a_header);
                    kind = a_header.kind;
                }
            }
            // The resolved pair, its child count and kind; a constant pair
            // has no children (its kind is never read).
            next = 0u;
            scratch_set_cell(frame, uint4(a, 0u));
            scratch_set_cell(frame + 1u, uint4(b, count));
            scratch_set_word(frame + 2u, 0u, kind);
            if (unify)
            {
                status = owned_constant_unify<Pair, Operation>(
                    a, b, count_domain, allow_inference, state, binding);
                if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
            }
        }
        uint2 shape = uint2(scratch_word(frame + 1u, 3u), scratch_word(frame + 2u, 0u));
        if (next == shape.x)
        {
            if (depth == 0u) return owned_constraint_ok();
            depth--; continue;
        }
        uint slot = next;
        scratch_set_word(frame, 3u, next + 1u);
        uint3 a_child = uint3(0u, 0u, OWNED_CONSTRAINT_INVALID); uint3 b_child = a_child;
        OwnedConstraintStatus status;
        [loop]
        for (uint side = 0u; side < 2u; side++)
        {
            bool first = side == 0u; uint3 child;
            status = owned_constraint_child<Pair>(select(bool3(first, first, first), a, b),
                shape.y, shape.x, slot, state.node_capacities, child);
            if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
            if (first) a_child = child; else b_child = child;
        }
        if (depth + 1u >= state.limits.depth)
            return owned_constraint_limit(5u, depth + 1u, state.limits.depth);
        bool child_count_domain = shape.y == 2u && slot == 1u;
        depth++;
        uint child_frame = SCRATCH_OWNED_UNIFY + depth * 3u;
        scratch_set_cell(child_frame, uint4(a_child, OWNED_CONSTRAINT_INVALID));
        scratch_set_cell(child_frame + 1u, uint4(b_child, 0u));
        scratch_set_cell(child_frame + 2u, uint4(0u, child_count_domain ? 1u : 0u, 0u, 0u));
    }
}

public OwnedConstraintStatus owned_constraints_begin<PatternGraph : IOwnedConstraintPatternGraph>(
    uint owner, uint pattern_node_capacity, uint goal_node_capacity, uint identity_capacity,
    OwnedConstraintLimits limits, uint frame, out OwnedConstraintState state)
{
    // GoalGraph does not participate in initialization: use a zero-inventory
    // pattern wrapper solely for its owner-count implementation.
    return owned_constraint_initialize<OwnedConstraintSelfRigidPair<PatternGraph>>(
        uint2(owner, OWNED_CONSTRAINT_INVALID), uint2(pattern_node_capacity, goal_node_capacity),
        identity_capacity, false, limits, frame, state);
}

// A head match (fixed = false: before finish, with inference) or a fixed
// prerequisite recheck (fixed = true, see owned_constraints_match_fixed),
// through one unification call site: a caller that runs both, such as
// implementation proof admission, expands the traversal once.
public OwnedConstraintStatus owned_constraints_match_or_fixed<
    PatternGraph : IOwnedConstraintPatternGraph, GoalGraph : IConstraintMatchGraph>(
    uint2 pattern, uint2 goal, bool fixed, inout OwnedConstraintState state)
{
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return state.status;
    if ((state.finished != 0u) != fixed || state.overlap != 0u ||
        state.owners.y != OWNED_CONSTRAINT_INVALID || any(state.counts.zw != uint2(0u, 0u)))
        state.status = owned_constraint_invalid(3u);
    else
    {
        if (fixed) for (uint domain = 0u; domain < 2u; domain++)
        {
            uint expected = owned_constraint_mask(state.counts[domain]);
            if (state.seen[domain] != expected || state.bound[domain] != expected)
            { state.status = owned_constraint_invalid(4u); break; }
        }
        if (state.status.state == OWNED_CONSTRAINT_MATCHED)
            state.status = owned_constraint_unify_root<
                OwnedConstraintGraphPair<PatternGraph, RigidConstraintGoalGraph<GoalGraph>>,
                OwnedOneWayBindingOperation>(pattern, goal, !fixed, state);
    }
    return state.status;
}

public OwnedConstraintStatus owned_constraints_match<
    PatternGraph : IOwnedConstraintPatternGraph, GoalGraph : IConstraintMatchGraph>(
    uint2 pattern, uint2 goal, inout OwnedConstraintState state)
{
    return owned_constraints_match_or_fixed<PatternGraph, GoalGraph>(pattern, goal, false, state);
}

// owned_constraints_finish and owned_constraint_binding in steps, for a caller
// that makes every constant resolution through its own single call site
// (substitution admission): owned_constraints_finish_checks runs the
// binding checks; while the state is MATCHED, each constant cell 0..63 that
// owned_constraints_recheck names is resolved by owned_constraints_resolve
// into OWNED_TARGETS_DISCARD, its status stored in state.status; a MATCHED
// state is then marked finished.
public OwnedConstraintStatus owned_constraints_finish_checks(inout OwnedConstraintState state)
{
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return state.status;
    if (state.overlap != 0u) state.status = owned_constraint_invalid(3u);
    else for (uint domain = 0u; domain < 2u; domain++)
    {
        uint expected = owned_constraint_mask(state.counts[domain]);
        if (state.seen[domain] != expected || state.bound[domain] != expected)
        { state.status = owned_constraint_invalid(4u); break; }
    }
    return state.status;
}
public bool owned_constraints_recheck(OwnedConstraintState state, uint cell, out uint3 term)
{ return owned_constant_recheck_term(state.counts, state.seen, state.frame, cell, term); }
public OwnedConstraintStatus owned_constraints_resolve<
    PatternGraph : IOwnedConstraintPatternGraph, GoalGraph : IConstraintMatchGraph>(
    uint3 term, uint targets, inout OwnedConstraintState state, out OwnedConstantResolution value)
{
    return owned_constant_resolve<
        OwnedConstraintGraphPair<PatternGraph, RigidConstraintGoalGraph<GoalGraph>>>(
        term, targets, state, value);
}

public OwnedConstraintStatus owned_constraints_finish<
    PatternGraph : IOwnedConstraintPatternGraph, GoalGraph : IConstraintMatchGraph>(
    inout OwnedConstraintState state)
{
    if (owned_constraints_finish_checks(state).state == OWNED_CONSTRAINT_MATCHED)
        state.status = owned_constant_recheck_fits<
            OwnedConstraintGraphPair<PatternGraph, RigidConstraintGoalGraph<GoalGraph>>>(state);
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
    return owned_constraints_match_or_fixed<PatternGraph, GoalGraph>(pattern, goal, true, state);
}

// The request of a finished state's bound variable. A type binding is
// complete here; a constant one returns its cell's term, which the caller
// resolves into OWNED_TARGETS_REQUEST and hands to
// owned_constraint_binding_resolved.
public bool owned_constraint_binding_begin(inout OwnedConstraintState state, bool constant,
    uint index, out OwnedConstraintBindingRequest request, out uint3 term)
{
    request = (OwnedConstraintBindingRequest)0;
    request.reference = uint3(0u, 0u, OWNED_CONSTRAINT_INVALID);
    term = uint3(0u, 0u, 0u);
    uint domain = constant ? 1u : 0u;
    if (state.status.state != OWNED_CONSTRAINT_MATCHED || state.finished == 0u || state.overlap != 0u ||
        index >= state.counts[domain] || index >= 32u ||
        (state.bound[domain] & (1u << index)) == 0u) return false;
    request.targets = OWNED_TARGETS_REQUEST;
    if (constant)
    {
        term = owned_constraint_constant_cell(state.frame, index).xyz;
        return true;
    }
    uint4 binding = owned_constraint_binding_cell(state.frame, index);
    if (binding.x != 1u || owned_constraint_constant(binding.y) || binding.w != 0u)
    { state.status = owned_constraint_invalid(2u); return false; }
    request.reference = binding.xyz;
    return true;
}
public bool owned_constraint_binding_resolved(inout OwnedConstraintState state,
    OwnedConstraintStatus status, OwnedConstantResolution value,
    inout OwnedConstraintBindingRequest request)
{
    state.status = status;
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return false;
    if (value.terminal.x != 1u || value.variable != OWNED_CONSTRAINT_INVALID)
    { state.status = owned_constraint_invalid(3u); return false; }
    // The resolution wrote its target list at OWNED_TARGETS_REQUEST.
    request.reference = value.terminal; request.target_count = value.target_count;
    return true;
}
public bool owned_constraint_binding<
    PatternGraph : IOwnedConstraintPatternGraph, GoalGraph : IConstraintMatchGraph>(
    inout OwnedConstraintState state, bool constant, uint index,
    out OwnedConstraintBindingRequest request)
{
    uint3 term;
    if (!owned_constraint_binding_begin(state, constant, index, request, term)) return false;
    if (!constant) return true;
    OwnedConstantResolution value;
    OwnedConstraintStatus status = owned_constraints_resolve<PatternGraph, GoalGraph>(
        term, OWNED_TARGETS_REQUEST, state, value);
    return owned_constraint_binding_resolved(state, status, value, request);
}

// Two-sided overlap over an explicit graph pair. Callers comparing two heads of
// one graph capability use OwnedConstraintSameGraphPair so both sides share code.
public OwnedConstraintStatus owned_overlap_begin_pair<Pair : IOwnedConstraintPair>(
    uint left_owner, uint right_owner, uint left_node_capacity, uint right_node_capacity,
    uint identity_capacity, OwnedConstraintLimits limits, uint frame, out OwnedConstraintState state)
{
    return owned_constraint_initialize<Pair>(uint2(left_owner, right_owner),
        uint2(left_node_capacity, right_node_capacity), identity_capacity, true, limits, frame, state);
}

public OwnedConstraintStatus owned_overlap_match_pair<Pair : IOwnedConstraintPair>(
    uint2 left, uint2 right, inout OwnedConstraintState state)
{
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return state.status;
    if (state.finished != 0u || state.overlap != 1u) state.status = owned_constraint_invalid(3u);
    else state.status = owned_constraint_unify_root<Pair,
        OwnedOverlapBindingOperation<Pair>>(left, right, true, state);
    return state.status;
}

public OwnedConstraintStatus owned_overlap_finish_pair<Pair : IOwnedConstraintPair>(
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
        state.status = owned_constant_recheck_fits<Pair>(state);
    if (state.status.state == OWNED_CONSTRAINT_MATCHED) state.finished = 1u;
    return state.status;
}

public OwnedConstraintStatus owned_overlap_begin<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    uint left_owner, uint right_owner, uint left_node_capacity, uint right_node_capacity,
    uint identity_capacity, OwnedConstraintLimits limits, uint frame, out OwnedConstraintState state)
{
    return owned_overlap_begin_pair<OwnedConstraintGraphPair<LeftGraph, RightGraph>>(
        left_owner, right_owner, left_node_capacity, right_node_capacity, identity_capacity, limits,
        frame, state);
}

public OwnedConstraintStatus owned_overlap_match<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    uint2 left, uint2 right, inout OwnedConstraintState state)
{ return owned_overlap_match_pair<OwnedConstraintGraphPair<LeftGraph, RightGraph>>(left, right, state); }

public OwnedConstraintStatus owned_overlap_finish<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph>(
    inout OwnedConstraintState state)
{ return owned_overlap_finish_pair<OwnedConstraintGraphPair<LeftGraph, RightGraph>>(state); }

// Definition admission visits EVERY head root independently of candidate
// comparisons. In particular, NoMatch must never hide an unconstrained header
// parameter or a malformed unused branch. Caller supplies subject followed by
// all ordered trait operands and admits their type/constant root roles.
public OwnedConstraintStatus owned_pattern_begin<PatternGraph : IOwnedConstraintPatternGraph>(
    uint owner, uint node_capacity, uint identity_capacity,
    OwnedConstraintLimits limits, uint frame, out OwnedConstraintState state)
{
    OwnedConstraintStatus status = owned_constraints_begin<PatternGraph>(
        owner, node_capacity, 0u, identity_capacity, limits, frame, state);
    state.overlap = 2u;
    return status;
}

public OwnedConstraintStatus owned_pattern_visit<PatternGraph : IOwnedConstraintPatternGraph>(
    uint2 root, inout OwnedConstraintState state)
{
    if (state.status.state != OWNED_CONSTRAINT_MATCHED) return state.status;
    if (state.overlap != 2u || state.finished != 0u)
        state.status = owned_constraint_invalid(3u);
    else state.status = owned_constraint_occurs<OwnedConstraintSelfRigidPair<PatternGraph>>(
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
        state.status = owned_constant_recheck_fits<OwnedConstraintSelfRigidPair<PatternGraph>>(state);
    if (state.status.state == OWNED_CONSTRAINT_MATCHED) state.finished = 1u;
    return state.status;
}
