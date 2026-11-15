// Closed layouts, one lane per TermId per level. The schema substitution
// stage supplies each nominal's exact field types, including compound and
// constant-generic fields. Arrays depend on their element layout; slices
// and references have fixed widths. Enum layouts remain unsupported here.
import type_checker.retention.projection.pj_types;
import native_value_layout;
import type_checker.retention.projection.pj_schema;

static const uint DIR_STRUCT = 5u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint t = pj_lane(dtid);
    uint terms = min(rt_counts[RT_A_TERMS], rt_capacity(RT_A_TERMS));
    if (t < RT_FIRST_TERM || t >= min(terms, pj_type_rows())) return;
    if (pj_layout[t].x != RT_INVALID) return;
    if (!rt_term_closed(t)) return;
    uint kind = rt_term_kind(t);
    if (kind == RT_KIND_REF || kind == RT_KIND_SLICE || kind == RT_KIND_ARRAY)
    {
        if (rt_term_arity(t) != (kind == RT_KIND_ARRAY ? 2u : 1u)) return;
        uint element = rt_term_arg(t, 0u);
        uint2 ref = pj_ref_of(element);
        if (ref.x == 0u) return;
        uint native_kind = kind == RT_KIND_REF ? 4u : kind == RT_KIND_SLICE ? 3u : 2u;
        uint width = kind == RT_KIND_REF ? 1u : NATIVE_SLICE_WORDS;
        uint count = RT_INVALID;
        if (kind == RT_KIND_ARRAY)
        {
            count = pj_array_count(t);
            uint stride = pj_words(element);
            if (count == RT_INVALID || stride == RT_INVALID ||
                (stride != 0u && count > (RT_INVALID - 1u) / stride)) return;
            width = stride * count;
        }
        ob_ti_kind[t] = native_kind;
        ob_ti_native_words[t] = width;
        ob_ti_elem_ref_tag[t] = ref.x;
        ob_ti_elem_ref_payload[t] = ref.y;
        if (kind == RT_KIND_ARRAY)
        {
            // Native length references name checked atoms, not raw counts.
            // The atom namespace is independent of the type namespace.
            ob_constant_atoms[t] = uint4(SCALAR_USIZE, count, 0u, 0u);
            ob_ti_len_kind[t] = 1u;
            ob_ti_len_payload[t] = t;
        }
        DeviceMemoryBarrier();
        pj_layout[t] = uint4(width, native_kind, count, 0u);
        InterlockedAdd(pj_status[PJ_S_LAYOUT_CHANGED], 1u);
        return;
    }
    if (kind != RT_KIND_NAMED) return;
    uint3 words = rt_term_words(t);
    uint entry = pj_dir_entry(words.x);
    if (entry == RT_INVALID) return;
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS + 0u];
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    uint4 d3 = rt_dir[entry * RT_DIR_WORDS + 3u];
    if (d0.y != DIR_STRUCT || d0.w != RT_DIR_COMMITTED || d3.w != 0u) return;
    uint types = d1.y & 0xffffu;
    if (rt_term_arity(t) != types + (d1.y >> 16u)) return;
    uint fields = 0u;
    uint total = 0u;
    for (uint k = 0u; k < d2.z; k++)
    {
        uint4 record = rt_schema[d2.y + k];
        if ((record.y & 0xffu) != RT_SCHEMA_FIELD) continue;
        uint field = pj_schema_type(t,k);
        uint w = pj_words(field);
        if (w == RT_INVALID) return;
        if (w >= RT_INVALID-total) return;
        total += w;
        fields++;
    }
    if (fields != d1.w || total == 0u) return;
    pj_layout[t] = uint4(total, 1u, fields, 0u);
    uint4 key = rt_decl_key[words.x];
    ob_ti_kind[t] = 1u;
    ob_ti_native_words[t] = total;
    ob_ti_len_payload[t] = 0u;
    ob_ext_library[t] = key.x;
    ob_ext_unit[t] = key.y;
    ob_ext_local[t] = key.w;
    ob_imported_layout_kind[t] = PJ_IMPORTED_STRUCT | PJ_IMPORTED_COMPLETE;
    InterlockedAdd(pj_status[PJ_S_LAYOUT_CHANGED], 1u);
}
