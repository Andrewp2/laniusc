// Included by the owned matcher. Constant conversion edges remain pure solver
// requests; the proof publisher owns graph allocation and final normalization.
uint owned_constant_fit_index(uint variable)
{ return (variable / 64u) * 32u + variable % 32u; }

uint owned_constant_scalar<Pair : IOwnedConstraintPair>(uint3 term)
{
    return Pair.constant_scalar(term.x, uint2(term.y & ~OWNED_CONSTRAINT_CONSTANT, term.z));
}

bool owned_constant_value_fits(uint3 value, uint mask)
{
    if (mask == 0u) return true;
    uint count;
    if (!constant_value_to_count(value, count)) return false;
    mask &= ~1u;
    while (mask != 0u)
    {
        uint scalar = firstbitlow(mask); uint3 converted;
        if (!constant_value_from_count(count, scalar, converted)) return false;
        mask &= mask - 1u;
    }
    return true;
}

OwnedConstraintStatus owned_constant_edge_work(inout OwnedConstraintState state)
{
    if (state.work.substitution_steps >= state.limits.substitution_steps)
        return owned_constraint_limit(8u, state.work.substitution_steps, state.limits.substitution_steps);
    state.work.substitution_steps++;
    return owned_constraint_ok();
}

OwnedConstraintStatus owned_constant_add_target(uint scalar,
    inout OwnedConstantResolution result, inout OwnedConstraintState state)
{
    if (!scalar_is_integer(scalar) || scalar >= 32u) return owned_constraint_invalid(2u);
    if (result.target_count + 1u >= state.limits.depth || result.target_count >= 63u)
        return owned_constraint_limit(5u, result.target_count + 1u, state.limits.depth);
    uint index = result.target_count++;
    scratch_set_word(result.targets + (index >> 2u), index & 3u, scalar);
    if (index == 0u) result.first_target = scalar;
    result.fit_mask |= 1u | (1u << scalar);
    return owned_constraint_ok();
}

// A successful resolution records its terminal's declared scalar, which is
// exactly owned_constant_scalar of that terminal: a valid literal's own value
// scalar, or a supported parameter scalar. Its target list is written to the
// scratch list `targets` (one OWNED_TARGETS_* role).
OwnedConstraintStatus owned_constant_resolve<Pair : IOwnedConstraintPair>(uint3 term,
    uint targets, inout OwnedConstraintState state, out OwnedConstantResolution result)
{
    result = (OwnedConstantResolution)0;
    result.targets = targets;
    result.variable = OWNED_CONSTRAINT_INVALID;
    result.terminal = uint3(0u, 0u, OWNED_CONSTRAINT_INVALID);
    uint4 visited = uint4(0u, 0u, 0u, 0u);
    uint3 checkpoint = term; uint span = 1u; uint since = 0u;
    for (uint work = 0u; work < 64u; work++)
    {
        if (term.x > 1u || term.z == OWNED_CONSTRAINT_INVALID || !owned_constraint_constant(term.y))
            return owned_constraint_invalid(1u);
        uint kind = term.y & ~OWNED_CONSTRAINT_CONSTANT;
        if (kind == 1u)
        {
            uint3 value;
            bool valid = Pair.constant_value(term.x, term.z, value);
            if (!valid || !constant_value_is_valid(value)) return owned_constraint_invalid(1u);
            if (!owned_constant_value_fits(value, result.fit_mask))
                return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
            result.concrete = 1u; result.terminal = term; result.value = value;
            result.result_scalar = value.x; result.terminal_scalar = value.x;
            if (result.target_count != 0u)
            {
                uint count;
                if (!constant_value_to_count(value, count) ||
                    !constant_value_from_count(count, result.first_target, result.value))
                    return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
                result.result_scalar = result.first_target;
            }
            return owned_constraint_ok();
        }
        uint3 next;
        if (kind == 2u)
        {
            bool valid = Pair.parameter_is_valid(term.x, term.z, true);
            // Exactly owned_constant_scalar of this parameter term.
            uint declared = Pair.parameter_scalar(term.x, term.z);
            uint scalar = constant_scalar_is_supported(declared) ? declared : 0u;
            if (!valid || !constant_scalar_is_supported(scalar)) return owned_constraint_invalid(3u);
            uint index;
            uint classification = Pair.owned_parameter(term.x,
                select(term.x == 0u, state.owners.x, state.owners.y), term.z, true, index);
            uint variable = OWNED_CONSTRAINT_INVALID;
            if (classification == OWNED_PARAMETER_BINDABLE)
            {
                uint domain = term.x * 2u + 1u;
                if (index >= state.counts[domain] || index >= 32u) return owned_constraint_invalid(3u);
                uint bit = 1u << index; variable = domain * 32u + index;
                uint fit_index = owned_constant_fit_index(variable);
                // An unseen variable's cell is stale: its term is unset and
                // its fit mask is zero.
                bool seen = (state.seen[domain] & bit) != 0u;
                uint4 constant_cell = owned_constraint_constant_cell(state.frame, fit_index);
                if (seen && any(constant_cell.xyz != term)) return owned_constraint_invalid(3u);
                state.seen[domain] |= bit;
                result.fit_mask |= seen ? constant_cell.w : 0u;
                scratch_set_cell(state.frame + OWNED_CONSTRAINT_BINDINGS + fit_index,
                    uint4(term, result.fit_mask));
                if ((state.bound[domain] & bit) != 0u)
                {
                    if ((visited[domain] & bit) != 0u) return owned_constraint_invalid(9u);
                    visited[domain] |= bit;
                    uint4 binding = owned_constraint_binding_cell(state.frame, variable);
                    if (binding.x > 1u || !owned_constraint_constant(binding.y) ||
                        binding.z == OWNED_CONSTRAINT_INVALID) return owned_constraint_invalid(2u);
                    uint binding_scalar = binding.w == 0u
                        ? owned_constant_scalar<Pair>(binding.xyz) : binding.w;
                    if (binding_scalar != scalar) return owned_constraint_invalid(2u);
                    if (binding.w != 0u)
                    {
                        OwnedConstraintStatus status = owned_constant_add_target(binding.w, result, state);
                        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
                    }
                    next = binding.xyz;
                }
                else
                {
                    result.variable = variable; result.terminal = term; result.terminal_scalar = scalar;
                    result.result_scalar = result.target_count == 0u ? scalar : result.first_target;
                    if (result.fit_mask != 0u && !scalar_is_integer(scalar))
                        return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
                    return owned_constraint_ok();
                }
            }
            else if (classification == OWNED_PARAMETER_RIGID)
            {
                result.terminal = term; result.terminal_scalar = scalar;
                result.result_scalar = result.target_count == 0u ? scalar : result.first_target;
                if (result.fit_mask != 0u && !scalar_is_integer(scalar))
                    return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
                return owned_constraint_ok();
            }
            else return owned_constraint_invalid(3u);
        }
        else if (kind == 3u)
        {
            uint scalar; uint2 child;
            bool valid = Pair.constant_projection(term.x, term.z, scalar, child);
            if (!valid || child.x < 1u || child.x > 3u || child.y == OWNED_CONSTRAINT_INVALID)
                return owned_constraint_invalid(1u);
            OwnedConstraintStatus status = owned_constant_add_target(scalar, result, state);
            if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
            next = uint3(term.x, OWNED_CONSTRAINT_CONSTANT | child.x, child.y);
        }
        else return owned_constraint_invalid(2u);
        OwnedConstraintStatus status = owned_constant_edge_work(state);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        if (all(next == checkpoint)) return owned_constraint_invalid(9u);
        since++;
        if (since == span) { checkpoint = next; span *= 2u; since = 0u; }
        term = next;
    }
    return owned_constraint_limit(5u, 64u, min(state.limits.depth, 64u));
}

// One binding: a checked type binding, or one chosen by constant unification.
struct OwnedConstantBinding
{
    uint bind;
    uint variable;
    uint3 value;
    uint target;
    // Constant bindings: revalidated through the resolver after installation.
    uint3 terminal;
}

// One resolved operand's fit duty. fit_mask is the operand's accumulated mask
// already combined with the caller's required mask.
OwnedConstraintStatus owned_constant_require_fits(uint concrete, uint3 value,
    uint terminal_scalar, uint variable, uint fit_mask, inout OwnedConstraintState state)
{
    if (concrete != 0u)
        return owned_constant_value_fits(value, fit_mask) ? owned_constraint_ok()
            : owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
    if (fit_mask != 0u && !scalar_is_integer(terminal_scalar))
        return owned_constraint_result(OWNED_CONSTRAINT_NO_MATCH, 0u);
    if (variable != OWNED_CONSTRAINT_INVALID)
    {
        // A resolved variable is seen, so its cell holds its own fit mask.
        uint fit_index = owned_constant_fit_index(variable);
        owned_constraint_set_fit_mask(state.frame, fit_index,
            owned_constraint_constant_cell(state.frame, fit_index).w | fit_mask);
    }
    return owned_constraint_ok();
}

// Require left then right through one call site; stops at the first failure.
// Callers fold mask into both operands' fit_mask after success.
OwnedConstraintStatus owned_constant_require_operand_fits(OwnedConstantResolution a,
    OwnedConstantResolution b, uint mask, inout OwnedConstraintState state)
{
    [loop]
    for (uint operand = 0u; operand < 2u; operand++)
    {
        bool first = operand == 0u;
        OwnedConstraintStatus status = owned_constant_require_fits(select(first, a.concrete, b.concrete),
            select(bool3(first, first, first), a.value, b.value),
            select(first, a.terminal_scalar, b.terminal_scalar), select(first, a.variable, b.variable),
            select(first, a.fit_mask, b.fit_mask) | mask, state);
        if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
    }
    return owned_constraint_ok();
}

OwnedConstraintStatus owned_constant_recheck_fits<Pair : IOwnedConstraintPair>(
    inout OwnedConstraintState state)
{
    for (uint side = 0u; side < 2u; side++)
    {
        uint domain = side * 2u + 1u;
        for (uint index = 0u; index < state.counts[domain]; index++)
        {
            uint fit_index = side * 32u + index;
            if ((state.seen[domain] & (1u << index)) == 0u) continue;
            uint4 constant_cell = owned_constraint_constant_cell(state.frame, fit_index);
            if (constant_cell.w == 0u) continue;
            OwnedConstantResolution value;
            OwnedConstraintStatus status = owned_constant_resolve<Pair>(
                constant_cell.xyz, OWNED_TARGETS_DISCARD, state, value);
            if (status.state != OWNED_CONSTRAINT_MATCHED) return status;
        }
    }
    return owned_constraint_ok();
}
