import type_checker.constant_parameter_slots;
// Read-only adapter over the including pass's checked metadata views. No
// substitution is performed here: method applicability infers a fresh local
// environment, and accepted call inference owns its later publication.
struct MethodReceiverGraph : IScopedTypeGraph
{
    static uint parameter_slot(uint token) { return type_generic_param_slot_by_token[token]; }
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
