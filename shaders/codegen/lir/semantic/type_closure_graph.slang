// Included after the native artifact buffers and params are declared. Closure
// needs checked structure only; declaration identity and native width are not
// inputs to deciding whether a type still contains symbolic parameters.
import type_checker.instance_arguments;
import type_checker.concrete_type_equality;
import type_checker.concrete_type_closure;

struct NativeTypeStructureGraph : ITypeStructureGraph
{
    static uint metadata(uint instance, uint field)
    {
        switch (field)
        {
        case 0u: return type_instance_kind[instance];
        case 2u: return type_instance_arg_count[instance];
        case 3u: return type_instance_elem_ref_tag[instance];
        case 4u: return type_instance_elem_ref_payload[instance];
        case 5u: return type_instance_len_kind[instance];
        case 6u: return type_instance_len_payload[instance];
        default: return 0xffffffffu;
        }
    }
    static bool argument(uint instance, uint ordinal, out uint tag, out uint payload)
    {
        return checked_instance_argument(instance, ordinal, gParams.n_tokens,
            type_instance_arg_count, type_instance_arg_start,
            type_instance_arg_ref_tag, type_instance_arg_ref_payload,
            type_instance_arg_row_start, type_instance_arg_row_count,
            type_instance_arg_row_ref_tag, type_instance_arg_row_ref_payload, tag, payload);
    }
}
