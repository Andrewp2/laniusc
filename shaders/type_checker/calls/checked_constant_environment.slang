import type_checker.concrete_type_equality;
import type_checker.constant_atoms_identity;
import type_checker.calls.constant_claim_identity;
import type_checker.constant_parameter_slots;
// Complete constant bindings, indexed by (callee, constant slot). References
// retain typed atoms, exact caller parameters, or checked count projections.
import type_checker.calls.claim_lookup;
import type_checker.calls.contextual_call_environment;
import type_checker.calls.explicit_call_environment;

public StructuredBuffer<uint> call_arg_row_count_out;
public StructuredBuffer<uint> call_const_claim_count_out;
public StructuredBuffer<uint> call_const_claim_callee;
public StructuredBuffer<uint> call_const_claim_slot;
public StructuredBuffer<uint> call_const_claim_ref_kind;
public StructuredBuffer<uint> call_const_claim_ref_payload;
public StructuredBuffer<uint> call_const_claim_identity_mode;
public StructuredBuffer<uint> call_const_claim_arg_row;
public StructuredBuffer<uint> call_const_claim_lookup_head;
public StructuredBuffer<uint> call_const_claim_lookup_next;

public bool checked_argument_environment_constant_binding(uint environment, uint slot,
    out uint kind, out uint value, out uint identity_mode, out uint selected_row)
{
    static const uint INVALID = 0xffffffffu;
    kind = 0u; value = INVALID; identity_mode = 0u; selected_row = INVALID;
    if (environment == INVALID || (environment & 0x80000000u) == 0u || slot >= 32u) return false;
    uint capacity; uint stride;
    call_const_claim_callee.GetDimensions(capacity, stride);
    uint count = min(call_const_claim_count_out[0u], capacity);
    if (count == 0u) return false;
    uint callee = environment & 0x7fffffffu;
    uint tokens = checked_source_constant_parameter_capacity();
    uint link = call_const_claim_lookup_head[call_claim_lookup_bucket(callee, slot, count)];
    for (uint step = 0u; step < count && link != 0u; step++)
    {
        uint row = link - 1u;
        if (row >= count) return false;
        if (call_const_claim_callee[row] == callee && call_const_claim_slot[row] == slot)
        {
            uint2 candidate = uint2(call_const_claim_ref_kind[row], call_const_claim_ref_payload[row]);
            uint mode = call_const_claim_identity_mode[row];
            // An unproduced provisional claim is not evidence. Every published
            // reference, including a projection, must pass the descriptor check.
            if (candidate.x != 0u || candidate.y != INVALID)
            {
                ConstantReferenceDescriptor descriptor; uint scalar;
                if (!checked_constant_claim_descriptor(candidate, mode, tokens, descriptor, scalar) ||
                    (selected_row != INVALID && !checked_constant_claims_compatible(
                        uint2(kind, value), identity_mode, candidate, mode, tokens))) return false;
                if (selected_row == INVALID || mode < identity_mode ||
                    (mode == identity_mode && row < selected_row))
                {
                    kind = candidate.x; value = candidate.y;
                    identity_mode = mode; selected_row = row;
                }
            }
        }
        link = call_const_claim_lookup_next[row];
    }
    return link == 0u && selected_row != INVALID;
}

public bool checked_argument_environment_constant_ref(uint environment, uint slot,
    out uint kind, out uint value)
{
    uint identity_mode; uint selected_row;
    return checked_argument_environment_constant_binding(environment, slot, kind, value,
        identity_mode, selected_row);
}

// Bindings are selected by evidence strength, not dispatch/lookup order:
// explicit, exact context, exact argument, count context, count argument.
// Strict validation still checks every argument and its original fit graph.
public bool checked_call_environment_constant_binding(uint environment, uint slot,
    out uint kind, out uint value, out uint identity_mode, out uint selected_row)
{
    static const uint INVALID = 0xffffffffu;
    kind = 0u; value = INVALID; identity_mode = 0u; selected_row = INVALID;
    uint tokens = checked_source_constant_parameter_capacity();
    ConstantReferenceDescriptor descriptor; uint scalar;
    if (checked_explicit_environment_constant(environment, slot, kind, value))
        return checked_constant_claim_descriptor(uint2(kind, value), 0u, tokens, descriptor, scalar);
    uint2 context; uint context_mode;
    bool has_context = checked_context_environment_constant_binding(environment, slot,
        context.x, context.y, context_mode);
    if (has_context && !checked_constant_claim_descriptor(context, context_mode, tokens, descriptor, scalar))
        return false;
    if (has_context && context_mode == 0u)
    { kind = context.x; value = context.y; return true; }
    uint2 argument; uint argument_mode; uint argument_row;
    bool has_argument = checked_argument_environment_constant_binding(environment, slot,
        argument.x, argument.y, argument_mode, argument_row);
    if (has_argument && argument_mode == 0u)
    {
        kind = argument.x; value = argument.y; selected_row = argument_row;
        return true;
    }
    if (has_context)
    {
        kind = context.x; value = context.y; identity_mode = context_mode;
        return true;
    }
    if (!has_argument) return false;
    kind = argument.x; value = argument.y; identity_mode = argument_mode;
    selected_row = argument_row;
    return true;
}

public bool checked_call_environment_constant_ref(uint environment, uint slot,
    out uint kind, out uint value)
{
    uint identity_mode; uint selected_row;
    return checked_call_environment_constant_binding(environment, slot, kind, value,
        identity_mode, selected_row);
}

public bool checked_call_constant_environment_rejected(uint callee)
{
    uint capacity; uint stride;
    call_const_claim_callee.GetDimensions(capacity, stride);
    uint count = min(call_const_claim_count_out[0u], capacity);
    if (count == 0u) return false;
    uint link = call_const_claim_lookup_head[call_claim_lookup_bucket(callee, 32u, count)];
    for (uint step = 0u; step < count && link != 0u; step++)
    {
        uint row = link - 1u;
        if (row >= count) return false;
        if (call_const_claim_callee[row] == callee && call_const_claim_slot[row] == 32u &&
            call_const_claim_ref_kind[row] == 0u) return true;
        link = call_const_claim_lookup_next[row];
    }
    return false;
}
