// Included after binding-operation definitions. No graph rows are allocated.
OwnedConstraintStatus owned_constant_suffix<Pair : IOwnedConstraintPair>(uint3 term, uint prefixes,
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
            if (!Pair.constant_projection(term.x, term.z, scalar, child)) return owned_constraint_invalid(1u);
            next = uint3(term.x, OWNED_CONSTRAINT_CONSTANT | child.x, child.y);
            projection = true;
        }
        else if (term.y == (OWNED_CONSTRAINT_CONSTANT | 2u))
        {
            uint index;
            uint classification = Pair.owned_parameter(term.x,
                select(term.x == 0u, state.owners.x, state.owners.y), term.z, true, index);
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

// Unify one constant pair, or, given type_binding.bind, install that checked
// type binding. One resolver call site resolves left, then right, then (after
// a new constant binding) revalidates the selected terminal; constant and type
// bindings share one binding-operation site (the overlap occurs traversal).
// The first result is retained before reusing b; budgets, mutations and the
// first failing status have exactly the order of the sequential steps.
OwnedConstraintStatus owned_constant_unify<Pair : IOwnedConstraintPair,
    Operation : IOwnedConstraintBindingOperation>(uint3 left, uint3 right,
    bool count_identity, bool allow_inference, inout OwnedConstraintState state,
    OwnedConstantBinding type_binding)
{
    OwnedConstantResolution a; OwnedConstantResolution b;
    OwnedConstraintStatus status;
    OwnedConstantBinding binding = type_binding;
    bool type_bind = type_binding.bind != 0u;
    uint3 term = left; uint phase = type_bind ? 3u : 0u;
    [loop]
    for (;;)
    {
        if (phase != 3u)
        {
            status = owned_constant_resolve<Pair>(term, state, b);
            if (status.state != OWNED_CONSTRAINT_MATCHED || phase == 2u) return status;
            if (phase == 0u) { a = b; term = right; phase = 1u; continue; }
            if (!count_identity && a.result_scalar != b.result_scalar)
                return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
            uint fits = a.fit_mask | b.fit_mask | (count_identity ? 1u : 0u);
            status = owned_constant_require_operand_fits(a, b, fits, state);
            if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
            a.fit_mask |= fits; b.fit_mask |= fits;
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
                    a.terminal_scalar != b.terminal_scalar)
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
                // Select the operand first: one suffix walk serves both sides.
                bool suffix_of_right = common == a.target_count && a_variable;
                if (!suffix_of_right && !(common == b.target_count && b_variable))
                    return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
                bind_left = suffix_of_right;
                status = owned_constant_suffix<Pair>(select(bool3(suffix_of_right, suffix_of_right,
                    suffix_of_right), right, left), common, state, value);
                if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
                value_scalar = owned_constant_scalar<Pair>(value);
            }
            uint selected_variable = bind_left ? a.variable : b.variable;
            uint other_variable = bind_left ? b.variable : a.variable;
            uint3 selected_terminal = bind_left ? a.terminal : b.terminal;
            uint declared_scalar = bind_left ? a.terminal_scalar : b.terminal_scalar;
            uint target = 0u;
            if (value_scalar != declared_scalar)
            {
                if (!count_equation || !scalar_is_integer(declared_scalar))
                    return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
                target = declared_scalar; fits |= 1u | (1u << declared_scalar);
            }
            if (count_equation && (a.target_count != 0u || b.target_count != 0u || count_identity))
                fits |= 1u;
            status = owned_constant_require_operand_fits(a, b, fits, state);
            if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
            if (selected_variable == other_variable)
            {
                // A count-preserving self equation admits finite values. Its fits are
                // already recorded; a recursive binding would manufacture a cycle.
                if (count_equation || (a.target_count == b.target_count)) return owned_constraint_ok();
                return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
            }
            binding.bind = 1u; binding.variable = selected_variable; binding.value = value;
            binding.target = target; binding.terminal = selected_terminal;
        }
        status = owned_constraint_bind<Operation>(binding.variable, binding.value,
            binding.target, type_bind, state);
        if (status.state != OWNED_CONSTRAINT_MATCHED || type_bind) return status;
        // Validate now, and preserve obligations for any later representative bind.
        term = binding.terminal; phase = 2u;
    }
}
