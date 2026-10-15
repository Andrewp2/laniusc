// Candidate-key row reads from the read-only checked type graph.
import type_checker.canonical.canonical_candidates;
import type_checker.checked_type_graph;

public struct CtCheckedRows : ICtRowReader
{
    [ForceInline] public static uint kind(uint row) { return type_instance_kind[row]; }
    [ForceInline] public static uint decl_token(uint row) { return type_instance_decl_token[row]; }
    [ForceInline] public static uint arg_count(uint row) { return type_instance_arg_count[row]; }
    [ForceInline] public static bool argument(uint row, uint index, out uint tag, out uint payload)
    { return ScopedCheckedTypeGraph.argument(row, index, tag, payload); }
    [ForceInline] public static uint2 elem(uint row)
    { return uint2(type_instance_elem_ref_tag[row], type_instance_elem_ref_payload[row]); }
    [ForceInline] public static uint2 len(uint row)
    { return uint2(type_instance_len_kind[row], type_instance_len_payload[row]); }
    [ForceInline] public static uint3 external(uint row)
    {
        return uint3(external_type_library_id[row], external_type_unit_id[row],
            external_type_local_index[row]);
    }
    [ForceInline] public static uint generic_slot(uint token)
    {
        uint count; uint stride;
        type_generic_param_slot_by_token.GetDimensions(count, stride);
        return token < count ? type_generic_param_slot_by_token[token] : 0xffffffffu;
    }
}
