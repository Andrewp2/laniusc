// Preserve the closed type graph for lowering consumers such as `?`.
// One lane per term, at most 32 arguments. The retained argument arena's
// disjoint ranges provide placement; no token-sized or fixed-slot expansion.
import type_checker.retention.projection_rows.retained_projection_type_tables;

public void project_closed_type_arguments(uint t)
{
    if (t >= pj_type_rows()) return;
    ob_ti_arg_row_start[t] = RT_INVALID;
    if (t == 0u) ob_ti_arg_row_count[0u] = rt_counts[RT_A_TERM_ARGS];
    if (!rt_is_stored_term(t) || t >= rt_counts[RT_A_TERMS] || !rt_term_closed(t)) return;
    uint kind = rt_term_kind(t);
    if (kind == RT_KIND_CC_VALUE)
    {
        ob_constant_atoms[t] = uint4(rt_term_words(t),0u);
        return;
    }
    if (kind != RT_KIND_NAMED) return;
    uint n = rt_term_arity(t);
    if (n > 32u) return;
    uint start = rt_term_meta[t].x;
    uint mask = rt_term_words(t).y;
    bool constant_seen = false;
    bool interleaved = false;
    for (uint k = 0u; k < n; k++)
    {
        uint arg = rt_term_arg(t,k);
        bool constant = (mask & (1u << k)) != 0u;
        uint2 ref = constant ? uint2(0x80000001u,arg) : pj_ref_of(arg);
        ob_ti_arg_row_ref_tag[start+k] = ref.x;
        ob_ti_arg_row_ref_payload[start+k] = ref.y;
        interleaved = interleaved || (constant_seen && !constant);
        constant_seen = constant_seen || constant;
    }
    ob_ti_arg_row_start[t] = start;
    ob_ti_arg_count[t] = n;
    ob_ti_len_kind[t] = (rt_term_head[t].x >> 16u) | (interleaved ? 0x80000000u : 0u);
    ob_ti_len_payload[t] = mask;
}
