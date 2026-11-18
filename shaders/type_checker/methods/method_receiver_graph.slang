import type_checker.constant_atoms;
import type_checker.constant_parameter_slots;
import type_checker.scoped_type_equality;
// Read-only adapter over the including pass's checked metadata views. No
// substitution is performed here: method applicability infers a fresh local
// environment, and accepted call inference owns its later publication.
struct MethodReceiverGraph : IScopedTypeGraph
{
    [ForceInline]
    static bool constant_value(uint row, out uint3 value)
    { return checked_constant_atom_value(row, value); }
    [ForceInline]
    static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    [ForceInline]
    static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return checked_constant_projection(row, scalar, child); }
    static bool parameter_is_valid(uint reference, bool constant)
    { return source_parameter_is_valid<MethodReceiverGraph>(reference, constant); }
    static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    { return source_substitute_type_parameter<MethodReceiverGraph>(environment, reference, tag, payload); }
    static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    { return source_substitute_constant_parameter<MethodReceiverGraph>(environment, reference, kind, value); }
    static uint parameter_slot(uint token) { return type_generic_param_slot_by_token[token]; }
    [ForceInline]
    static uint constant_parameter_slot(uint token) { return type_const_param_slot_by_token[token]; }
    static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    { tag = 0u; payload = 0xffffffffu; return false; }
    static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { kind = 0u; value = 0xffffffffu; return false; }
    static uint metadata(uint instance, uint field)
    {
        switch (field)
        {
        case 0u: return type_instance_kind[instance];
        case 1u: return type_instance_decl_token[instance];
        case 2u: return type_instance_arg_count[instance];
        case 3u: return type_instance_elem_ref_tag[instance];
        case 4u: return type_instance_elem_ref_payload[instance];
        case 5u: return type_instance_len_kind[instance];
        case 6u: return type_instance_len_payload[instance];
        case 7u: return external_type_library_id[instance];
        case 8u: return external_type_unit_id[instance];
        case 9u: return external_type_local_index[instance];
        default: return 0xffffffffu;
        }
    }
    static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    {
        uint tokens; uint stride;
        type_generic_param_slot_by_token.GetDimensions(tokens, stride);
        return checked_instance_argument(instance, slot, tokens,
            type_instance_arg_count, type_instance_arg_start,
            type_instance_arg_ref_tag, type_instance_arg_ref_payload,
            type_instance_arg_row_start, type_instance_arg_row_count_out,
            type_instance_arg_row_ref_tag, type_instance_arg_row_ref_payload, tag, payload);
    }
}

uint method_receiver_type_capacity()
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return capacity;
}
