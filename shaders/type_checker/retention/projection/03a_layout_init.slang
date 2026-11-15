// Projection step 3a: one lane per TermId row of the type tables. Resets
// the layouts and writes the lowering type tables' "no instance" values.
import type_checker.retention.projection.pj_types;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint t = pj_lane(dtid);
    if (t >= pj_type_rows()) return;
    pj_layout[t] = uint4(RT_INVALID, 0u, 0u, 0u);
    ob_ti_kind[t] = 0u;
    ob_ti_native_words[t] = RT_INVALID;
    ob_ti_decl_token[t] = RT_INVALID;
    ob_ti_elem_ref_tag[t] = 0u;
    ob_ti_elem_ref_payload[t] = RT_INVALID;
    ob_ti_len_kind[t] = 0u;
    ob_ti_len_payload[t] = RT_INVALID;
    ob_ti_arg_count[t] = 0u;
    ob_ti_arg_start[t] = RT_INVALID;
    ob_ext_library[t] = RT_INVALID;
    ob_ext_unit[t] = RT_INVALID;
    ob_ext_local[t] = RT_INVALID;
    ob_imported_layout_kind[t] = 0u;
}

