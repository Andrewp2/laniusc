// Canonical IDs of a call's parameter patterns and argument operands, shared
// by argument collection (03a) and claim emission (03a1). Included after
// argument_value_reference.slang; the including kernel imports the canonical
// API, canonical_candidates, canonical_dependency, ct_spare, ct_checked and
// its row reader.

// Parameter slots of the callee's patterns: a local parameter by its
// declaration's slot, a dependency parameter by the slot it carries.
struct ClaimSlots : ICtSlots
{
    uint type_slot(uint token)
    {
        uint slot = generic_slot_for_type_ref(TYPE_REF_GENERIC_PARAM, token);
        return slot < CT_SLOT_NONE ? slot : CT_SLOT_NONE;
    }
    uint const_slot(uint token)
    {
        uint slot = valid_token(token) ? type_const_param_slot_by_token[token] : INVALID;
        return slot < CT_SLOT_NONE ? slot : CT_SLOT_NONE;
    }
    uint const_scalar(uint token)
    {
        uint scalar = valid_token(token) ? type_const_param_scalar_by_token[token] : 0u;
        return constant_scalar_is_supported(scalar) ? scalar : 0u;
    }
}

// The canonical ID of a parameter pattern or argument operand: a dependency
// node (its alias root's) or slot parameter, else the checked row interned.
uint operand_id<R : ICtRowReader>(uint2 operand, inout CtSpare spare)
{
    if (operand.x == TYPE_REF_EXTERNAL_GENERIC)
        return operand.y < CT_DEP_PARAM_SLOTS ? ct_dep_type_param(operand.y) : CT_UNKNOWN;
    if (operand.x != TYPE_REF_EXTERNAL_CANONICAL)
        return ct_intern_checked<R>(operand.x, operand.y, spare.record);
    uint roots; uint stride;
    canonical_type_roots.GetDimensions(roots, stride);
    return operand.y < roots ? ct_dependency_state(canonical_type_roots[operand.y]) : CT_UNKNOWN;
}
