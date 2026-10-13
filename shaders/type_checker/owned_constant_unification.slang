// Included after binding-operation definitions. No graph rows are allocated.
OwnedConstraintStatus owned_constant_suffix<LeftGraph : IOwnedConstraintPatternGraph,
    RightGraph : IOwnedConstraintPatternGraph>(uint3 term, uint prefixes,
    inout OwnedConstraintState state, out uint3 suffix)
{
    suffix = term;
    if (prefixes == 0u) return owned_constraint_ok();
    for (uint work = 0u; work < 64u; work++)
    {
        uint3 next; bool projection = false;
        if (term.y == (OWNED_CONSTRAINT_CONSTANT | 3u))
        {
            uint scalar; uint2 child;
            bool valid = term.x == 0u ? LeftGraph.constant_projection(term.z, scalar, child)
                                      : RightGraph.constant_projection(term.z, scalar, child);
            if (!valid) return owned_constraint_invalid(1u);
            next = uint3(term.x, OWNED_CONSTRAINT_CONSTANT | child.x, child.y);
            projection = true;
        }
        else if (term.y == (OWNED_CONSTRAINT_CONSTANT | 2u))
        {
            uint index;
            uint classification = term.x == 0u
                ? LeftGraph.owned_parameter(state.owners.x, term.z, true, index)
                : RightGraph.owned_parameter(state.owners.y, term.z, true, index);
            uint domain = term.x * 2u + 1u;
            if (classification != OWNED_PARAMETER_BINDABLE || index >= state.counts[domain] ||
                (state.bound[domain] & (1u << index)) == 0u) return owned_constraint_invalid(3u);
            uint4 edge = state.bindings[domain * 32u + index];
            next = edge.xyz; projection = edge.w != 0u;
        }
        else return owned_constraint_invalid(2u);
        OwnedConstraintStatus status = owned_constant_edge_work(state);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        if (projection && --prefixes == 0u) { suffix = next; return owned_constraint_ok(); }
        term = next;
    }
    return owned_constraint_limit(5u, 64u, 64u);
}

OwnedConstraintStatus owned_constant_unify<
    LeftGraph : IOwnedConstraintPatternGraph, RightGraph : IOwnedConstraintPatternGraph,
    Operation : IOwnedConstraintBindingOperation>(uint3 left, uint3 right,
    bool count_identity, bool allow_inference, inout OwnedConstraintState state)
{
    OwnedConstantResolution a; OwnedConstantResolution b;
    OwnedConstraintStatus status;
    // Resolve left then right through one traversal call site. The first
    // result is retained before reusing b; budgets, mutations and the first
    // failing status have exactly the same order as two sequential calls.
    [loop]
    for (uint operand = 0u; operand < 2u; operand++)
    {
        uint3 term = operand == 0u ? left : right;
        status = owned_constant_resolve<LeftGraph, RightGraph>(term, state, b);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        if (operand == 0u) a = b;
    }
    if (!count_identity && a.result_scalar != b.result_scalar)
        return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
    uint fits = a.fit_mask | b.fit_mask | (count_identity ? 1u : 0u);
    status = owned_constant_require_fits<LeftGraph, RightGraph>(a, fits, state);
    if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
    status = owned_constant_require_fits<LeftGraph, RightGraph>(b, fits, state);
    if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
    if (a.concrete != 0u && b.concrete != 0u)
    {
        bool equal = all(a.value == b.value);
        if (count_identity)
        {
            uint ac; uint bc;
            equal = constant_value_to_count(a.value, ac) && constant_value_to_count(b.value, bc) && ac == bc;
        }
        return equal ? owned_constraint_ok() : owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
    }
    bool a_variable = a.variable != OWNED_CONSTRAINT_INVALID;
    bool b_variable = b.variable != OWNED_CONSTRAINT_INVALID;
    if (!a_variable && !b_variable)
    {
        // Concrete and unresolved symbolic expressions are not identical.
        if (a.concrete != b.concrete || a.terminal.z != b.terminal.z ||
            owned_constant_scalar<LeftGraph, RightGraph>(a.terminal) !=
                owned_constant_scalar<LeftGraph, RightGraph>(b.terminal))
            return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
        if (!count_identity)
        {
            if (a.target_count != b.target_count)
                return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
            for (uint i = 0u; i < a.target_count; i++)
                if (a.target_scalars[i] != b.target_scalars[i])
                    return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
        }
        return owned_constraint_ok();
    }
    if (!allow_inference) return owned_constraint_invalid(4u);
    bool bind_left = a_variable;
    uint3 value = bind_left ? right : left;
    uint value_scalar = bind_left ? b.result_scalar : a.result_scalar;
    // Overlap asks for a concrete common instance. Different unary prefixes
    // impose fits on one count; ordinary result scalar equality was checked.
    bool count_equation = count_identity || a.concrete != 0u || b.concrete != 0u ||
        (Operation.mode() == 1u && (a.target_count != 0u || b.target_count != 0u));
    if (!count_equation)
    {
        uint common = 0u;
        while (common < a.target_count && common < b.target_count &&
            a.target_scalars[common] == b.target_scalars[common]) common++;
        // Only an exposed variable can capture an exact symbolic suffix.
        if (common == a.target_count && a_variable)
        {
            bind_left = true;
            status = owned_constant_suffix<LeftGraph, RightGraph>(right, common, state, value);
        }
        else if (common == b.target_count && b_variable)
        {
            bind_left = false;
            status = owned_constant_suffix<LeftGraph, RightGraph>(left, common, state, value);
        }
        else return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        if (!count_equation) value_scalar = owned_constant_scalar<LeftGraph, RightGraph>(value);
    }
    uint selected_variable = bind_left ? a.variable : b.variable;
    uint other_variable = bind_left ? b.variable : a.variable;
    uint3 selected_terminal = bind_left ? a.terminal : b.terminal;
    uint declared_scalar = owned_constant_scalar<LeftGraph, RightGraph>(selected_terminal);
    uint target = 0u;
    if (value_scalar != declared_scalar)
    {
        if (!count_equation || !scalar_is_integer(declared_scalar))
            return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
        target = declared_scalar; fits |= 1u | (1u << declared_scalar);
    }
    if (count_equation && (a.target_count != 0u || b.target_count != 0u || count_identity))
        fits |= 1u;
    status = owned_constant_require_fits<LeftGraph, RightGraph>(a, fits, state);
    if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
    status = owned_constant_require_fits<LeftGraph, RightGraph>(b, fits, state);
    if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
    if (selected_variable == other_variable)
    {
        // A count-preserving self equation admits finite values. Its fits are
        // already recorded; a recursive binding would manufacture a cycle.
        if (count_equation || (a.target_count == b.target_count)) return owned_constraint_ok();
        return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
    }
    status = Operation.validate(selected_variable, value, state);
    if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
    uint domain = selected_variable / 32u; uint index = selected_variable % 32u;
    state.bindings[selected_variable] = uint4(value, target);
    state.bound[domain] |= 1u << index;
    // Validate now, and preserve obligations for any later representative bind.
    OwnedConstantResolution rebound;
    return owned_constant_resolve<LeftGraph, RightGraph>(selected_terminal, state, rebound);
}
