// Reserve a private checked node. Its owner publishes kind after all children
// are complete; later dispatches are the publication boundary for other lanes.
uint allocate_application(uint declaration, uint arguments, uint length_kind,
    uint length, uint library, uint unit, uint local_index)
{
    uint ordinal = atomic_u32_add(type_application_count, 0u, 1u);
    uint source_capacity; uint stride;
    type_generic_param_slot_by_token.GetDimensions(source_capacity, stride);
    uint base = source_capacity + 64u;
    if (base > mutable_type_capacity() || ordinal >= mutable_type_capacity() - base)
        return INVALID;
    uint target = base + ordinal;
    type_instance_kind[target] = 0u;
    type_instance_decl_token[target] = declaration;
    type_instance_arg_count[target] = arguments;
    type_instance_arg_start[target] = source_capacity * 4u + 64u * 32u + ordinal * 32u;
    type_instance_arg_row_start[target] = INVALID;
    type_instance_elem_ref_tag[target] = 0u;
    type_instance_elem_ref_payload[target] = INVALID;
    type_instance_len_kind[target] = length_kind;
    type_instance_len_payload[target] = length;
    external_type_library_id[target] = library;
    external_type_unit_id[target] = unit;
    external_type_local_index[target] = local_index;
    type_instance_state[target] = 1u;
    type_instance_aggregate_word_count[target] = 0u;
    type_native_word_count[target] = INVALID;
    type_native_scalar_identity[target] = 0u;
    return target;
}
