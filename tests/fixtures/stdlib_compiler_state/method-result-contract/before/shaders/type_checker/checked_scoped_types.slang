// Resolve a checked field reference under its concrete receiver scope.
import type_checker.checked_type_graph;
import type_checker.scoped_reference_lookup;
import type_checker.concrete_type_closure;

public StructuredBuffer<uint> type_instance_lookup_head;
public StructuredBuffer<uint> type_instance_lookup_next;

public bool checked_instance_is_closed(uint instance, uint token_capacity)
{
    return concrete_instance_is_closed(instance, checked_type_capacity(),
        type_instance_kind, type_instance_arg_count, type_instance_arg_start,
        type_instance_arg_ref_tag, type_instance_arg_ref_payload,
        type_instance_arg_row_start, type_instance_arg_row_count_out,
        type_instance_arg_row_ref_tag, type_instance_arg_row_ref_payload,
        type_instance_elem_ref_tag, type_instance_elem_ref_payload, type_instance_len_kind,
        token_capacity);
}

public bool checked_scoped_reference(uint tag, uint payload, uint context,
    uint token_capacity, out uint result_tag, out uint result_payload)
{
    static const uint INVALID = 0xffffffffu;
    result_tag = 0u; result_payload = INVALID;
    uint instance_capacity = checked_type_capacity();
    if (tag == 3u && payload < instance_capacity && checked_instance_is_closed(payload, token_capacity))
    {
        result_tag = tag; result_payload = payload;
        return true;
    }
    return instance_scoped_reference<ScopedCheckedTypeGraph>(tag, payload, context,
        instance_capacity, token_capacity, type_instance_lookup_head, type_instance_lookup_next,
        result_tag, result_payload);
}
