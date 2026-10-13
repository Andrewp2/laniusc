import type_checker.constant_atoms;
import type_checker.constant_parameter_slots;
import type_checker.concrete_type_equality;
// Read-only checked type graph shared by field checking and native layout.
// Concrete applications are selected by complete scoped type identity, never
// by native width. Declaration-side instance rows remain immutable.
import type_checker.scoped_type_equality;
import type_checker.concrete_type_closure;
import type_checker.instance_arguments;

public StructuredBuffer<uint> type_instance_kind;
public StructuredBuffer<uint> type_instance_decl_token;
public StructuredBuffer<uint> type_instance_arg_count;
public StructuredBuffer<uint> type_instance_arg_start;
public StructuredBuffer<uint> type_instance_arg_ref_tag;
public StructuredBuffer<uint> type_instance_arg_ref_payload;
public StructuredBuffer<uint> type_instance_arg_row_start;
public StructuredBuffer<uint> type_instance_arg_row_count_out;
public StructuredBuffer<uint> type_instance_arg_row_ref_tag;
public StructuredBuffer<uint> type_instance_arg_row_ref_payload;
public StructuredBuffer<uint> type_instance_elem_ref_tag;
public StructuredBuffer<uint> type_instance_elem_ref_payload;
public StructuredBuffer<uint> type_instance_len_kind;
public StructuredBuffer<uint> type_instance_len_payload;
public StructuredBuffer<uint> external_type_library_id;
public StructuredBuffer<uint> external_type_unit_id;
public StructuredBuffer<uint> external_type_local_index;
public StructuredBuffer<uint> type_generic_param_slot_by_token;
public uint checked_type_capacity()
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return capacity;
}

public struct ScopedCheckedTypeGraph : IScopedTypeGraph
{
    public static bool constant_value(uint row, out uint3 value)
    { return checked_constant_atom_value(row, value); }
    public static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return checked_constant_projection(row, scalar, child); }
    public static bool parameter_is_valid(uint reference, bool constant)
    { return source_parameter_is_valid<ScopedCheckedTypeGraph>(reference, constant); }
    public static bool substitute_type_parameter(uint environment, uint reference, out uint tag, out uint payload)
    { return source_substitute_type_parameter<ScopedCheckedTypeGraph>(environment, reference, tag, payload); }
    public static bool substitute_constant_parameter(uint environment, uint reference, out uint kind, out uint value)
    { return source_substitute_constant_parameter<ScopedCheckedTypeGraph>(environment, reference, kind, value); }
    public static bool environment_argument(uint environment, uint slot, out uint tag, out uint payload)
    { return application_environment_type_argument<ScopedCheckedTypeGraph>(environment, slot, tag, payload); }
    public static uint constant_parameter_slot(uint token) { return type_const_param_slot_by_token[token]; }
    public static bool environment_constant(uint environment, uint slot, out uint kind, out uint value)
    { return application_environment_constant<ScopedCheckedTypeGraph>(environment, slot, kind, value); }
    public static uint parameter_slot(uint token) { return type_generic_param_slot_by_token[token]; }
    public static uint metadata(uint instance, uint field)
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
    public static bool argument(uint instance, uint slot, out uint tag, out uint payload)
    {
        static const uint INVALID = 0xffffffffu;
        tag = 0u; payload = INVALID;
        uint tokens; uint token_stride;
        type_generic_param_slot_by_token.GetDimensions(tokens, token_stride);
        return checked_instance_argument(instance, slot, tokens,
            type_instance_arg_count, type_instance_arg_start,
            type_instance_arg_ref_tag, type_instance_arg_ref_payload,
            type_instance_arg_row_start, type_instance_arg_row_count_out,
            type_instance_arg_row_ref_tag, type_instance_arg_row_ref_payload, tag, payload);
    }
}
